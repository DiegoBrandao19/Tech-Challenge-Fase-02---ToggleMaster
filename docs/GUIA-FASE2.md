# ToggleMaster – Fase 2 | Guia de execução (AWS Academy, Opção A)

Região usada em todos os comandos: `us-east-1`. Ordem recomendada: **1 → 7**.

## 0. Ajustes feitos no código original (mencionar no vídeo – "desafios encontrados")
| Problema encontrado | Correção |
|---|---|
| `auth-service/go.mod` com `require github.com/jackc/pgx/v4/stdlib` (não é um módulo) | linha removida |
| `evaluation-service/go.sum` era uma cópia do `go.mod` (corrompido) | removido; `go mod tidy` regenera no build |
| `auth-service` sem `go.sum` | `go mod tidy` no Dockerfile |
| Flask 2.2.2 quebra com Werkzeug 3.x | `Werkzeug==2.2.3` fixado no build |
| boto3 1.26 não aceita endpoint customizado p/ DynamoDB Local | boto3 1.34.162 + `AWS_ENDPOINT_URL_DYNAMODB` (só no compose) |

## 1. Local – docker compose (9 contêineres)
```bash
cp .env.example .env     # preencha AWS_SQS_URL e credenciais AWS (AWS Academy > AWS Details)
docker compose up -d --build
docker compose ps        # 5 apps + postgres-auth + postgres-flags + redis + dynamodb-local (+ dynamodb-init que termina)
curl localhost:8001/health ; curl localhost:8002/health ; curl localhost:8003/health ; curl localhost:8004/health ; curl localhost:8005/health
```
Fluxo de teste (chave de serviço já semeada: `tm_key_local_dev_evaluation_service`):
```bash
K=tm_key_local_dev_evaluation_service
curl -X POST localhost:8002/flags -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"name":"enable-new-dashboard","is_enabled":true}'
curl -X POST localhost:8003/rules -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"flag_name":"enable-new-dashboard","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}'
curl "localhost:8004/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```
> O compose tem 4 data stores locais (2 PostgreSQL, Redis, DynamoDB Local). O SQS não tem emulador: o evaluation/analytics usam a fila SQS real. Sem `AWS_SQS_URL` válida o analytics encerra (exige as 3 variáveis).

## 2. Infra AWS (Console)
Crie nesta ordem, **todos na mesma VPC** (default) e região:
1. **SQS** → Standard → `togglemaster-queue`. Anote a URL.
2. **DynamoDB** → tabela `ToggleMasterAnalytics`, partition key `event_id` (String), on-demand.
3. **ECR** → 5 repositórios (ou rode `scripts/build-push.sh`, que cria e publica).
4. **RDS PostgreSQL ×3** (Free tier/`db.t3.micro`, sem acesso público): `auth-db` (db `auth_db`), `flags-db` (db `flags_db`), `targeting-db` (db `targeting_db`). Anote endpoints/usuário/senha.
5. **ElastiCache Redis** (cluster cache, `cache.t3.micro`, sem criptografia em trânsito para a URL `redis://` funcionar). Anote o endpoint primário.
6. **Security Groups**: nos SGs do RDS e do ElastiCache, libere 5432 / 6379 com origem = **SG do cluster EKS** (security group do node group), nunca 0.0.0.0/0.
7. **EKS (Console)**: Create cluster → Cluster role **LabRole** → Node group gerenciado → Node role **LabRole**, `t3.medium`, Min=1 / Desired=2 / Max=4.
```bash
aws eks update-kubeconfig --region us-east-1 --name <nome-do-cluster>
kubectl get nodes
```

## 3. Imagens no ECR
```bash
./scripts/build-push.sh            # imprime ECR_REGISTRY=...
export ECR_REGISTRY=<valor impresso>
```

## 4. Metrics Server e Nginx Ingress
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes     # aguarde ~1 min

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml
kubectl get svc -n ingress-nginx ingress-nginx-controller   # EXTERNAL-IP = hostname do NLB
```

## 5. Deploy
```bash
kubectl apply -f k8s/00-namespaces.yaml
export AUTH_DATABASE_URL='postgres://USER:PASS@<rds-auth>:5432/auth_db'
export FLAGS_DATABASE_URL='postgres://USER:PASS@<rds-flags>:5432/flags_db'
export TARGETING_DATABASE_URL='postgres://USER:PASS@<rds-targeting>:5432/targeting_db'
export MASTER_KEY='admin-secreto-123'
export REDIS_URL='redis://<elasticache-endpoint>:6379'
export AWS_SQS_URL='https://sqs.us-east-1.amazonaws.com/<conta>/togglemaster-queue'
export SERVICE_API_KEY='PENDENTE'                 # será trocada no passo 5.2
./scripts/gen-secrets.sh && ./scripts/deploy.sh
```
**5.2 Chave de serviço do evaluation** (o auth-service gera a chave aleatória):
```bash
LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -X POST http://$LB/auth/admin/keys -H "Authorization: Bearer $MASTER_KEY" -H 'Content-Type: application/json' -d '{"name":"evaluation-service"}'
export SERVICE_API_KEY=tm_key_...   # a chave retornada
./scripts/gen-secrets.sh && kubectl rollout restart deploy/evaluation-service -n evaluation
```
> Segredos reais ficam só no cluster; os `secret.yaml` do repositório contêm placeholders em base64.

Rotas do Ingress: `/auth/*`→auth (`/auth/validate`, `/auth/admin/keys`), `/flags`→flag, `/targeting/*`→targeting (`/targeting/rules/..`), `/evaluate`→evaluation. O analytics é um worker (só ClusterIP).

Verificação:
```bash
kubectl get pods -A | grep -E 'auth|flags|targeting|evaluation|analytics'
curl http://$LB/flags -H "Authorization: Bearer $SERVICE_API_KEY"
curl "http://$LB/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```
(Crie antes a flag e a regra via `/flags` e `/targeting/rules`, como no passo 1.)

## 6. Demonstração de escalabilidade
**evaluation-service (HPA CPU 70%)** – 3 terminais:
```bash
watch kubectl get hpa -n evaluation
watch kubectl get pods -n evaluation
hey -z 3m -c 100 "http://$LB/evaluate?user_id=u1&flag_name=enable-new-dashboard"     # ou: ab -n 200000 -c 100 "..."
```
**analytics-service (HPA CPU 50%)** – envie muitas mensagens à fila:
```bash
for i in $(seq 1 3000); do
  aws sqs send-message --queue-url "$AWS_SQS_URL" --message-body "{\"user_id\":\"u$i\",\"flag_name\":\"enable-new-dashboard\",\"result\":true,\"timestamp\":\"2026-11-01T12:00:00Z\"}" >/dev/null &
  (( i % 50 == 0 )) && wait
done; wait
watch kubectl get hpa -n analytics ; kubectl logs -n analytics deploy/analytics-service -f
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT
```
Dica: o analytics gasta pouca CPU (fica em long-polling); por isso o `request` é 50m e o alvo 50%. Se não escalar, rode o loop de envio em paralelo mais de uma vez ou reduza `averageUtilization`.
Evaluation gera mensagens na fila sozinho a cada `/evaluate`, então o `hey` também alimenta o analytics.

## 7. Roteiro do vídeo (≤ 20 min)
1. (1 min) Arquitetura: 5 serviços, 3 data stores, fluxo evaluate→Redis/flag/targeting→SQS→analytics→DynamoDB.
2. (3 min) `docker compose up` → `docker compose ps` (9 contêineres) → fluxo de curl.
3. (3 min) Console AWS: EKS, ECR (5 repos), RDS ×3, ElastiCache, DynamoDB, SQS.
4. (3 min) `kubectl get nodes`, `get pods -A`, `get ingress -A`, `curl` no LB (Nginx Ingress).
5. (4 min) Carga com `hey` → `get hpa` / `get pods` crescendo no evaluation.
6. (3 min) Mensagens no SQS → HPA do analytics → itens na tabela DynamoDB.
7. (3 min) Explicações: **HPA×KEDA** (Academy não permite criar IAM roles/IRSA que o KEDA precisa para ler `queueDepth`; HPA por CPU é o workaround: fila cheia → mais processamento → mais CPU), **RDS** (relacional/transacional, flags e regras), **ElastiCache** (cache de baixa latência, TTL 30 s no hot path), **DynamoDB** (NoSQL de alta escrita, eventos sem schema fixo/sem joins), desafios (LabRole, SGs, bugs do código – tabela da seção 0).

## 8. Limpeza (evita consumir créditos do Academy)
`kubectl delete ns auth flags targeting evaluation analytics ingress-nginx` (remove o NLB) → deletar EKS node group/cluster, RDS ×3, ElastiCache, ECR, SQS, DynamoDB.
