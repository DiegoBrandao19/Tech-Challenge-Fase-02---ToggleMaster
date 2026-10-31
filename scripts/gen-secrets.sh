#!/usr/bin/env bash
# Gera os Secrets REAIS (valores em base64) a partir de variáveis de ambiente e aplica no cluster.
# Uso: exporte as variáveis abaixo e rode ./scripts/gen-secrets.sh
set -euo pipefail
: "${AUTH_DATABASE_URL:?}" "${MASTER_KEY:?}" "${FLAGS_DATABASE_URL:?}" "${TARGETING_DATABASE_URL:?}"
: "${REDIS_URL:?}" "${SERVICE_API_KEY:?}" "${AWS_SQS_URL:?}"
mk() { # ns name k=v...
  ns=$1; name=$2; shift 2; args=()
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  kubectl create secret generic "$name" -n "$ns" "${args[@]}" --dry-run=client -o yaml | kubectl apply -f -
}
mk auth       auth-service-secret       "DATABASE_URL=$AUTH_DATABASE_URL" "MASTER_KEY=$MASTER_KEY"
mk flags      flag-service-secret       "DATABASE_URL=$FLAGS_DATABASE_URL"
mk targeting  targeting-service-secret  "DATABASE_URL=$TARGETING_DATABASE_URL"
mk evaluation evaluation-service-secret "REDIS_URL=$REDIS_URL" "SERVICE_API_KEY=$SERVICE_API_KEY" "AWS_SQS_URL=$AWS_SQS_URL"
mk analytics  analytics-service-secret  "AWS_SQS_URL=$AWS_SQS_URL"
echo "Secrets aplicados (armazenados em base64 pelo Kubernetes)."
