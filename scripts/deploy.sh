#!/usr/bin/env bash
# Deploy completo no EKS. Pré-requisitos: kubectl apontando p/ o cluster, imagens já no ECR,
# Metrics Server e Nginx Ingress instalados (ver docs/AWS-SETUP.md) e gen-secrets.sh executado
# (rode gen-secrets.sh DEPOIS do passo 1 abaixo, ou apenas rode este script duas vezes).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ECR_REGISTRY:?ex: 123456789012.dkr.ecr.us-east-1.amazonaws.com}"
export IMAGE_TAG=${IMAGE_TAG:-v1}

echo "1/5 Namespaces";  kubectl apply -f k8s/00-namespaces.yaml
echo "2/5 ConfigMaps e Services"
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  kubectl apply -f k8s/$s/configmap.yaml -f k8s/$s/service.yaml
done
echo "3/5 Init dos bancos RDS (Jobs)"
for pair in auth-service:auth flag-service:flags targeting-service:targeting; do
  s=${pair%%:*}; ns=${pair##*:}
  kubectl create configmap $s-db-init -n $ns --from-file=init.sql=$s/db/init.sql --dry-run=client -o yaml | kubectl apply -f -
  kubectl delete job $s-db-init -n $ns --ignore-not-found
  kubectl apply -f k8s/$s/db-init-job.yaml
  kubectl wait --for=condition=complete job/$s-db-init -n $ns --timeout=120s
done
echo "4/5 Deployments"
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  envsubst '${ECR_REGISTRY} ${IMAGE_TAG}' < k8s/$s/deployment.yaml | kubectl apply -f -
done
echo "5/5 Ingress e HPA"
for s in auth-service flag-service targeting-service evaluation-service; do kubectl apply -f k8s/$s/ingress.yaml; done
kubectl apply -f k8s/evaluation-service/hpa.yaml -f k8s/analytics-service/hpa.yaml
kubectl get pods -A | grep -E 'auth|flags|targeting|evaluation|analytics'
