Archivos IAM para crear role de instancia (EC2) que pueda asumir LabRole

Qué contiene:
- `trust-ec2.json`: trust policy para el role de EC2 (principal: ec2.amazonaws.com).
- `assume-lab-policy.json`: política que permite que el role de EC2 llame `sts:AssumeRole` sobre el LabRole. Reemplaza `ARN_DEL_LABROLE` por el ARN real del LabRole (por ejemplo `arn:aws:iam::478701513931:role/LabRole`).

Flujo recomendable (ejecutar desde la instancia o desde una máquina con AWS CLI y permisos IAM completos):
1) Revisar y reemplazar placeholders en `iam/assume-lab-policy.json`.
2) Ejecutar el script `scripts/setup_instance_role.sh` pasando `--instance-id` y `--lab-role-arn`.

Ejemplo:

cd ~/cloud-computing-tarea-1
# editar iam/assume-lab-policy.json y poner el ARN real
chmod +x scripts/setup_instance_role.sh
sudo scripts/setup_instance_role.sh --instance-id i-0123456789abcdef0 --lab-role-arn arn:aws:iam::478701513931:role/LabRole

Notas importantes:
- El usuario que ejecute el script debe tener permisos IAM y EC2 (create-role, put-role-policy, create-instance-profile, add-role-to-instance-profile, associate-iam-instance-profile).
- Si LabRole pertenece a otra cuenta (p. ej. la cuenta del curso), el administrador de esa cuenta debe actualizar la trust policy del LabRole para confiar en el role de instancia (ARN del role que creamos). Si no pueden editar LabRole, pide al admin del curso que lo hagan.
- Estos archivos sirven como evidencia en la entrega (puedes commitearlos). No incluyas secretos en el repo.
