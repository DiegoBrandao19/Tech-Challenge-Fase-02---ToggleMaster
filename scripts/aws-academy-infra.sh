#!/usr/bin/env bash
# AWS Academy (Learner Lab): SQS, DynamoDB, RDS x3 e ElastiCache no VPC do cluster EKS.
# O CLUSTER EKS é criado pelo CONSOLE (LabRole), conforme o enunciado.
# Uso:  ./scripts/aws-academy-infra.sh base     # SQS + DynamoDB (segundos)
#       ./scripts/aws-academy-infra.sh data     # RDS x3 + ElastiCache (10-15 min) - rode DEPOIS de criar o cluster
#       ./scripts/aws-academy-infra.sh destroy  # apaga SQS, DynamoDB, RDS e ElastiCache
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_REGION=${AWS_REGION:-us-east-1} AWS_PAGER=""
QUEUE_NAME=${QUEUE_NAME:-togglemaster-queue}
DDB_TABLE=${DDB_TABLE:-ToggleMasterAnalytics}
CLUSTER=${CLUSTER:-togglemaster}
mkdir -p aws; OUT=aws/outputs.env

base() {
  aws sqs create-queue --queue-name "$QUEUE_NAME" >/dev/null
  SQS_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --query QueueUrl --output text)
  aws dynamodb create-table --table-name "$DDB_TABLE" \
    --attribute-definitions AttributeName=event_id,AttributeType=S \
    --key-schema AttributeName=event_id,KeyType=HASH --billing-mode PAY_PER_REQUEST >/dev/null || echo "(tabela já existe)"
  echo "export AWS_REGION=$AWS_REGION AWS_SQS_URL=$SQS_URL" > $OUT
  echo "SQS: $SQS_URL"; echo "DynamoDB: $DDB_TABLE"
}

data() {
  PASS=${DB_PASSWORD:-$(openssl rand -hex 10)}
  VPC=$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.vpcId --output text)
  CSG=$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
  SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text)
  echo "VPC=$VPC CLUSTER_SG=$CSG"; echo "SUBNETS=$SUBNETS"
  DBSG=$(aws ec2 create-security-group --group-name tm-data-sg --description "ToggleMaster data stores" --vpc-id $VPC --query GroupId --output text)
  for port in 5432 6379; do
    aws ec2 authorize-security-group-ingress --group-id $DBSG --protocol tcp --port $port --source-group $CSG >/dev/null
  done
  aws rds create-db-subnet-group --db-subnet-group-name tm-subnets --db-subnet-group-description tm --subnet-ids $SUBNETS >/dev/null
  aws elasticache create-cache-subnet-group --cache-subnet-group-name tm-cache-subnets --cache-subnet-group-description tm --subnet-ids $SUBNETS >/dev/null
  for n in auth flags targeting; do
    aws rds create-db-instance --db-instance-identifier tm-$n --engine postgres --db-instance-class db.t3.micro \
      --allocated-storage 20 --storage-type gp2 --master-username tmadmin --master-user-password "$PASS" \
      --db-name ${n}_db --vpc-security-group-ids $DBSG --db-subnet-group-name tm-subnets \
      --no-publicly-accessible --backup-retention-period 0 >/dev/null
  done
  aws elasticache create-cache-cluster --cache-cluster-id tm-redis --engine redis --cache-node-type cache.t3.micro \
    --num-cache-nodes 1 --cache-subnet-group-name tm-cache-subnets --security-group-ids $DBSG >/dev/null
  echo "Aguardando RDS e ElastiCache (10-15 min)..."
  for n in auth flags targeting; do aws rds wait db-instance-available --db-instance-identifier tm-$n; done
  aws elasticache wait cache-cluster-available --cache-cluster-id tm-redis
  ep() { aws rds describe-db-instances --db-instance-identifier tm-$1 --query 'DBInstances[0].Endpoint.Address' --output text; }
  REDIS=$(aws elasticache describe-cache-clusters --cache-cluster-id tm-redis --show-cache-node-info --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text)
  cat >> $OUT <<EOT
export AUTH_DATABASE_URL='postgres://tmadmin:$PASS@$(ep auth):5432/auth_db'
export FLAGS_DATABASE_URL='postgres://tmadmin:$PASS@$(ep flags):5432/flags_db'
export TARGETING_DATABASE_URL='postgres://tmadmin:$PASS@$(ep targeting):5432/targeting_db'
export REDIS_URL='redis://$REDIS:6379'
export MASTER_KEY='admin-secreto-123'
export SERVICE_API_KEY='PENDENTE'
EOT
  echo "Pronto. Rode: source $OUT   (contém senhas: NÃO commitar nem mostrar no vídeo)"
}

destroy() {
  for n in auth flags targeting; do aws rds delete-db-instance --db-instance-identifier tm-$n --skip-final-snapshot --delete-automated-backups >/dev/null || true; done
  aws elasticache delete-cache-cluster --cache-cluster-id tm-redis >/dev/null || true
  for n in auth flags targeting; do aws rds wait db-instance-deleted --db-instance-identifier tm-$n || true; done
  aws elasticache wait cache-cluster-deleted --cache-cluster-id tm-redis || true
  aws rds delete-db-subnet-group --db-subnet-group-name tm-subnets || true
  aws elasticache delete-cache-subnet-group --cache-subnet-group-name tm-cache-subnets || true
  aws ec2 delete-security-group --group-id "$(aws ec2 describe-security-groups --filters Name=group-name,Values=tm-data-sg --query 'SecurityGroups[0].GroupId' --output text)" || true
  aws sqs delete-queue --queue-url "$(aws sqs get-queue-url --queue-name $QUEUE_NAME --query QueueUrl --output text)" || true
  aws dynamodb delete-table --table-name $DDB_TABLE >/dev/null || true
  echo "Agora apague o cluster e o node group pelo Console (EKS), o NLB (kubectl delete ns ingress-nginx) e os repositórios ECR."
}
"$1"
