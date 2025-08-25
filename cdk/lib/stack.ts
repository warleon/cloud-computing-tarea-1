import { Stack, StackProps, Duration, RemovalPolicy } from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecs from "aws-cdk-lib/aws-ecs";
import * as ecsPatterns from "aws-cdk-lib/aws-ecs-patterns";

export class EcsCrudStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const vpc = new ec2.Vpc(this, "Vpc", { maxAzs: 2 });

    const cluster = new ecs.Cluster(this, "Cluster", { vpc });

    const service = new ecsPatterns.ApplicationLoadBalancedFargateService(
      this,
      "Service",
      {
        cluster,
        cpu: 256,
        desiredCount: 1,
        memoryLimitMiB: 512,
        publicLoadBalancer: true,
        listenerPort: 80,
        taskImageOptions: {
          image: ecs.ContainerImage.fromAsset(".."), // build desde raíz del proyecto (Dockerfile)
          containerPort: 8000,
          enableLogging: true,
          environment: {},
        },
        assignPublicIp: false,
      }
    );

    // Volumen efímero para /data (SQLite)
    const volName = "data";
    service.taskDefinition.addVolume({ name: volName });
    service.taskDefinition.defaultContainer?.addMountPoints([
      { containerPath: "/data", sourceVolume: volName, readOnly: false },
    ]);

    // Health check por /health
    service.targetGroup.configureHealthCheck({
      path: "/health",
      healthyHttpCodes: "200",
      interval: Duration.seconds(30),
    });

    // Auto-destroy logs (opcional):
    service.service.node.addDependency(service.listener);
  }
}
