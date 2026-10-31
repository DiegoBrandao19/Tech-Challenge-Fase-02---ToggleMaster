#!/usr/bin/env bash
# Build das 5 imagens e push para o ECR (cria os repositórios se não existirem).
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=${AWS_REGION:-us-east-1}; TAG=${IMAGE_TAG:-v1}
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REG
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr describe-repositories --repository-names $s --region $REGION >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name $s --region $REGION >/dev/null
  docker build -t $REG/$s:$TAG ./$s
  docker push $REG/$s:$TAG
done
echo "ECR_REGISTRY=$REG"
