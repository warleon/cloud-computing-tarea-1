#!/usr/bin/env bash
set -euo pipefail

# Script para crear un role de EC2 que permita asumir el LabRole y asociarlo a una instancia.
# Uso: sudo ./scripts/setup_instance_role.sh --instance-id i-... --lab-role-arn arn:aws:iam::...:role/LabRole

print_usage(){
  cat <<EOF
Usage: $0 --instance-id INSTANCE_ID --lab-role-arn LAB_ROLE_ARN
Example:
  sudo $0 --instance-id i-0123456789abcdef0 --lab-role-arn arn:aws:iam::478701513931:role/LabRole
EOF
}

INSTANCE_ID=""
LAB_ROLE_ARN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-id) INSTANCE_ID="$2"; shift 2;;
    --lab-role-arn) LAB_ROLE_ARN="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 1;;
  esac
done

if [[ -z "$INSTANCE_ID" || -z "$LAB_ROLE_ARN" ]]; then
  echo "Missing required args" >&2
  print_usage
  exit 1
fi

ROLE_NAME=EC2AssumeLabRole
INSTANCE_PROFILE_NAME=EC2AssumeLabRole
POLICY_NAME=AllowAssumeLabRole

echo "Creating role ${ROLE_NAME} with EC2 trust policy..."
aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://iam/trust-ec2.json || true

# prepare policy file by replacing placeholder if present
if grep -q "ARN_DEL_LABROLE" iam/assume-lab-policy.json; then
  echo "Replacing placeholder in iam/assume-lab-policy.json with ${LAB_ROLE_ARN}"
  sed -e "s|ARN_DEL_LABROLE|${LAB_ROLE_ARN}|g" iam/assume-lab-policy.json > iam/assume-lab-policy.tmp && mv iam/assume-lab-policy.tmp iam/assume-lab-policy.json
fi

echo "Attaching inline policy ${POLICY_NAME} to role ${ROLE_NAME}..."
aws iam put-role-policy --role-name ${ROLE_NAME} --policy-name ${POLICY_NAME} --policy-document file://iam/assume-lab-policy.json

echo "Creating instance profile ${INSTANCE_PROFILE_NAME} (if not exists)..."
aws iam create-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} || true

echo "Adding role to instance profile..."
aws iam add-role-to-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} --role-name ${ROLE_NAME} || true

echo "Associating instance profile to instance ${INSTANCE_ID}..."
aws ec2 associate-iam-instance-profile --instance-id ${INSTANCE_ID} --iam-instance-profile Name=${INSTANCE_PROFILE_NAME} || true

echo "Done. Verifica la asociación y prueba assume-role desde la instancia."

echo "Describe association (may take a few seconds to appear):"
aws ec2 describe-iam-instance-profile-associations --filters Name=instance-id,Values=${INSTANCE_ID} --output json

echo "Después, prueba: aws sts assume-role --role-arn ${LAB_ROLE_ARN} --role-session-name pruebaLabRole"
