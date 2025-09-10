import os, json, pulumi
import pulumi_aws as aws
import pulumi_docker as docker

ACCOUNT_ID    = os.getenv("ACCOUNT_ID")
REGION        = os.getenv("REGION", "us-east-1")
LAB_ROLE_ARN  = os.getenv("LAB_ROLE_ARN")  # arn:aws:iam::<account>:role/LabRole

BUILD_CONTEXT = os.getenv("BUILD_CONTEXT", "..")
DOCKERFILE    = os.getenv("DOCKERFILE", "Dockerfile")

CONTAINER_PORT = int(os.getenv("CONTAINER_PORT", "8000"))
HEALTH_PATH    = os.getenv("HEALTH_PATH", "/")

REPO_NAME   = os.getenv("REPO_NAME", "crud-sqlite-api")
IMAGE_TAG   = os.getenv("IMAGE_TAG", "v1")
IMAGE_URI   = os.getenv("IMAGE_URI")  # Si ya existe imagen en ECR, úsala y no construyas

if not (ACCOUNT_ID and LAB_ROLE_ARN):
    raise Exception("Debes exportar ACCOUNT_ID y LAB_ROLE_ARN.")

aws.config.region = REGION

# VPC/subnets por defecto
vpc = aws.ec2.get_vpc(default=True)
subnets = aws.ec2.get_subnets(filters=[aws.ec2.GetSubnetsFilterArgs(
    name="vpc-id", values=[vpc.id]
)])

# SGs
alb_sg = aws.ec2.SecurityGroup("alb-sg",
    vpc_id=vpc.id, description="ALB ingress 80",
    ingress=[aws.ec2.SecurityGroupIngressArgs(protocol="tcp", from_port=80, to_port=80, cidr_blocks=["0.0.0.0/0"])],
    egress=[aws.ec2.SecurityGroupEgressArgs(protocol="-1", from_port=0, to_port=0, cidr_blocks=["0.0.0.0/0"])]
)

task_sg = aws.ec2.SecurityGroup("task-sg",
    vpc_id=vpc.id, description="Tasks allow app port from ALB",
    ingress=[aws.ec2.SecurityGroupIngressArgs(protocol="tcp", from_port=CONTAINER_PORT, to_port=CONTAINER_PORT, security_groups=[alb_sg.id])],
    egress=[aws.ec2.SecurityGroupEgressArgs(protocol="-1", from_port=0, to_port=0, cidr_blocks=["0.0.0.0/0"])]
)

# Imagen
if IMAGE_URI:
    repository_url = IMAGE_URI.rsplit(":", 1)[0]
else:
    repo = aws.ecr.Repository("repo", name=REPO_NAME, force_delete=True,
        image_scanning_configuration=aws.ecr.RepositoryImageScanningConfigurationArgs(scan_on_push=True))
    repository_url = repo.repository_url
    auth = aws.ecr.get_authorization_token(registry_id=repo.registry_id)
    image = docker.Image("built-image",
        build=docker.DockerBuild(context=BUILD_CONTEXT, dockerfile=DOCKERFILE),
        image_name=pulumi.Output.concat(repository_url, ":", IMAGE_TAG),
        registry=docker.Registry(
            server=pulumi.Output.from_input(repository_url).apply(lambda u: u.split("/")[0]),
            username=auth.user_name, password=auth.password
        )
    )
    IMAGE_URI = image.image_name

# ECS + Logs
cluster = aws.ecs.Cluster("cluster", name="crudapi-pulumi-cluster")
log_group = aws.cloudwatch.LogGroup("log", name="/ecs/crudapi-pulumi", retention_in_days=7)

image_uri_out   = pulumi.Output.from_input(IMAGE_URI)     # puede venir como str o Output[str]
log_name_out    = log_group.name                          # Output[str]
container_port  = pulumi.Output.from_input(CONTAINER_PORT)
health_path_out = pulumi.Output.from_input(HEALTH_PATH)

container_def = pulumi.Output.all(
    image_uri=image_uri_out,
    log_group=log_name_out,
    cport=container_port,
    hpath=health_path_out,
).apply(lambda a: json.dumps([{
    "name": "app",
    "image": a["image_uri"],
    "essential": True,
    "portMappings": [{
        "containerPort": int(a["cport"]),
        "protocol": "tcp"
    }],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": a["log_group"],
            "awslogs-region": REGION,
            "awslogs-stream-prefix": "app"
        }
    },
    # (opcional pero recomendado) healthcheck del contenedor
    "healthCheck": {
        "command": ["CMD-SHELL", f"curl -f http://localhost:{int(a['cport'])}{a['hpath']} || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3
    }
}], separators=(',', ':')))

task = aws.ecs.TaskDefinition("task",
    family="crudapi-pulumi-task",
    requires_compatibilities=["FARGATE"],
    network_mode="awsvpc",
    cpu="256", memory="512",
    execution_role_arn=LAB_ROLE_ARN, task_role_arn=LAB_ROLE_ARN,
    container_definitions=container_def
)

# ALB
alb = aws.lb.LoadBalancer("alb",
    load_balancer_type="application",
    security_groups=[alb_sg.id], subnets=subnets.ids
)
tg = aws.lb.TargetGroup("tg",
    vpc_id=vpc.id, target_type="ip",
    port=CONTAINER_PORT, protocol="HTTP",
    health_check=aws.lb.TargetGroupHealthCheckArgs(path=HEALTH_PATH, protocol="HTTP", matcher="200-399")
)
listener = aws.lb.Listener("listener",
    load_balancer_arn=alb.arn, port=80, protocol="HTTP",
    default_actions=[aws.lb.ListenerDefaultActionArgs(type="forward", target_group_arn=tg.arn)]
)

service = aws.ecs.Service("svc",
    name="crudapi-pulumi-svc",
    cluster=cluster.arn, task_definition=task.arn,
    desired_count=1, launch_type="FARGATE",
    network_configuration=aws.ecs.ServiceNetworkConfigurationArgs(
        assign_public_ip=True, security_groups=[task_sg.id], subnets=subnets.ids
    ),
    load_balancers=[aws.ecs.ServiceLoadBalancerArgs(target_group_arn=tg.arn, container_name="app", container_port=CONTAINER_PORT)],
    opts=pulumi.ResourceOptions(depends_on=[listener])
)

pulumi.export("alb_dns", alb.dns_name)
pulumi.export("image_uri", IMAGE_URI)
pulumi.export("container_port", CONTAINER_PORT)
pulumi.export("health_path", HEALTH_PATH)
