# ToggleMaster – Tech Challenge Fase 02 (FIAP/POSTECH)

Containerização e orquestração em Kubernetes (Amazon EKS) dos 5 microsserviços do ToggleMaster, uma plataforma de *feature flags*.

**Aluno:** Diego Barbosa Brandão Rocha · **RM:** 375936 · **Discord:** coddp
**Vídeo de demonstração:** https://drive.google.com/file/d/1mqH5t_KD3duUJQ1pzlUIT-kIqB1e3VE-/view?usp=sharing
**Relatório de entrega:** [`RELATORIO_ENTREGA.pdf`](RELATORIO_ENTREGA.pdf)

## Arquitetura

```
Cliente → Nginx Ingress (NLB) → evaluation-service → Redis (cache) · flag-service · targeting-service
evaluation-service → fila SQS → analytics-service → DynamoDB
```

| Serviço | Linguagem | Porta | Dados |
|---|---|---|---|
| auth-service | Go | 8001 | PostgreSQL (RDS) |
| flag-service | Python | 8002 | PostgreSQL (RDS) |
| targeting-service | Python | 8003 | PostgreSQL (RDS) |
| evaluation-service | Go | 8004 | Redis (ElastiCache) + SQS |
| analytics-service | Python | 8005 | SQS → DynamoDB |

## Conteinerização
- Dockerfiles **multi-stage** nos 5 serviços: Go em `distroless/static:nonroot`; Python em `python:3.11-slim`, usuário não-root (uid 10001) e gunicorn.
- `.dockerignore` em cada serviço.

## Execução local (Docker Compose)
9 contêineres: 5 aplicações + 2 PostgreSQL + Redis + DynamoDB Local. O override `docker-compose.local-sqs.yml` adiciona o ElasticMQ, um emulador de SQS, para rodar sem conta AWS.

```bash
docker compose -f docker-compose.yml -f docker-compose.local-sqs.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.local-sqs.yml ps
```

Atenção: rode em um terminal **sem** variáveis AWS carregadas (`AWS_SQS_URL`, `AWS_PROFILE` etc.), senão os contêineres tentam usar a fila real.

## Execução na AWS (EKS)
Infraestrutura usada (AWS Academy Learner Lab, `us-east-1`, `LabRole`): EKS (node group 2 × t3.medium), 5 repositórios ECR, 3 RDS PostgreSQL, 1 ElastiCache Redis, 1 tabela DynamoDB e 1 fila SQS Standard, além de Metrics Server e Nginx Ingress.

Resumo (detalhes em [`docs/GUIA-FASE2.md`](docs/GUIA-FASE2.md)):

```bash
./scripts/aws-academy-infra.sh base     # SQS + DynamoDB
# criar o cluster EKS e o node group (Console)
./scripts/aws-academy-infra.sh data     # RDS x3 + ElastiCache
./scripts/build-push.sh                 # build e push das imagens para o ECR
# instalar o Nginx Ingress (Helm)
kubectl apply -f k8s/00-namespaces.yaml
./scripts/gen-secrets.sh                # Secrets a partir de variáveis de ambiente
./scripts/deploy.sh                     # ConfigMaps, Services, Jobs, Deployments, Ingress e HPAs
```

Os arquivos `k8s/*/secret.yaml` contêm apenas **placeholders**; os valores reais são gerados por `scripts/gen-secrets.sh` e nunca são commitados.

## Kubernetes
- Um Namespace por serviço; Deployments com requests/limits e probes de readiness/liveness em `/health`; Services ClusterIP; ConfigMaps e Secrets; Ingress Nginx.
- Rotas: `/auth`, `/flags`, `/targeting` e `/evaluate`.
- Jobs de inicialização dos bancos (`CREATE TABLE IF NOT EXISTS`).

## Escalabilidade (HPA)
| Serviço | Métrica | Alvo | Réplicas |
|---|---|---|---|
| evaluation-service | CPU | 70% | 2 – 6 |
| analytics-service | CPU | 50% | 1 – 5 |

**Por que HPA por CPU e não KEDA (Opção A, AWS Academy):** o KEDA precisaria de um role IAM (IRSA) para ler a profundidade da fila SQS, e o Learner Lab só permite a `LabRole`. Com a fila cheia, o analytics processa mais mensagens, a CPU sobe e o HPA escala.

**Teste de carga** (`hey`, 3 min, 100 conexões): 119.431 requisições, todas `200`, ~663 req/s; evaluation de 2 para 6 réplicas, analytics até 5 réplicas, mais de 100 mil eventos gravados no DynamoDB.

## Por que três bancos
- **RDS PostgreSQL** (auth, flag, targeting): dados relacionais e transacionais, um banco por microsserviço.
- **ElastiCache Redis** (evaluation): cache de baixa latência no caminho crítico, com TTL.
- **DynamoDB** (analytics): alto volume de escrita de eventos, sem esquema fixo e sem joins.

## Estrutura
```
├── <serviço>/            código e Dockerfile de cada microsserviço
├── docker-compose*.yml   ambiente local
├── k8s/                  manifestos Kubernetes
├── scripts/              provisionamento, build/push, secrets e deploy
├── local/                seeds e configuração do ambiente local
└── docs/                 guia, roteiros de gravação e relatório
```

Repositórios originais dos microsserviços: https://github.com/FIAP-TCs
