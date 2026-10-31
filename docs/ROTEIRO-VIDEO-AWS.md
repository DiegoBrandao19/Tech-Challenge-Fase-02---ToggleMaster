# Roteiro do vídeo – ToggleMaster Fase 2 (AWS) — máx. 20 min

Cada passo tem: **O que estamos fazendo** (entenda), **O que falar** (sugestão de fala) e **Comando**.
Fale com suas palavras, as falas são só um guia. Nenhum comando contém `;` — se ao colar aparecer `\;`, apague.

---

## PREPARAÇÃO (fora da gravação)

Abra 3 terminais na pasta `fase2`. Em todos:
```bash
export AWS_PROFILE=Academy AWS_REGION=us-east-1 AWS_PAGER=""
```
No terminal 1 (principal) carregue as variáveis e limpe a tela (**não mostre na gravação**):
```bash
source aws/outputs.env
export ECR_REGISTRY=882429616809.dkr.ecr.us-east-1.amazonaws.com
export IMAGE_TAG=v1
export SERVICE_API_KEY=$(kubectl get secret evaluation-service-secret -n evaluation -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)
export LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
clear
```
Nos terminais 2 e 3 rode só o `export LB=...`.
Abas do Console abertas: EKS, ECR, RDS, ElastiCache, DynamoDB, SQS. Fonte do terminal grande.

**Nunca mostrar:** `cat aws/outputs.env`, `echo $SERVICE_API_KEY`, `env`, `kubectl get secret -o yaml`, `cat k8s/*/secret.yaml`.

---

## 1. Abertura e arquitetura (1 min)

**O que estamos fazendo:** apresentando o projeto e o desenho da solução antes de mostrar a infraestrutura.

**O que falar:**
"Olá, eu sou o Diego Barbosa Brandão Rocha, e este é o Tech Challenge da Fase 2. O ToggleMaster é uma plataforma de feature flags com cinco microserviços: auth-service, que gera e valida chaves de API. flag-service, que cadastra as flags. targeting-service, que guarda as regras de segmentação. evaluation-service, que é o caminho quente: recebe a pergunta 'essa flag está ligada para este usuário?' e responde. E o analytics-service, que consome eventos de uma fila e grava no DynamoDB. Na AWS, tudo roda em um cluster EKS. Os três primeiros serviços usam bancos PostgreSQL no RDS, o evaluation usa Redis no ElastiCache como cache, e os eventos passam pela fila SQS até o DynamoDB. A entrada é um Nginx Ingress com um Load Balancer."

---

## 2. Tour pelo Console AWS (3 min)

**O que estamos fazendo:** provando que a infraestrutura exigida existe. Mostre cada serviço e diga o nome e a função.

| Tela | O que mostrar | O que falar |
|---|---|---|
| **EKS** → cluster `togglemaster` → aba *Computação* | grupo de nós `tm-nodes`, 2 nós t3.medium, escala 1/2/4 | "Este é o cluster Kubernetes gerenciado. Os nós são EC2 t3.medium em um node group, com mínimo 1, desejado 2 e máximo 4." |
| **ECR** | 5 repositórios, tag `v1` | "Aqui ficam as imagens Docker dos 5 serviços, geradas com multi-stage build e rodando com usuário não-root." |
| **RDS** | 3 instâncias `tm-auth`, `tm-flags`, `tm-targeting` | "Três bancos PostgreSQL separados, um por serviço, porque cada microserviço é dono dos seus dados." |
| **ElastiCache** | `tm-redis` | "Redis usado pelo evaluation-service como cache, para não consultar flag e targeting a cada requisição." |
| **DynamoDB** | tabela `ToggleMasterAnalytics` (chave `event_id`) | "Banco NoSQL onde o analytics grava os eventos de avaliação." |
| **SQS** | fila `togglemaster-queue` | "Fila Standard que desacopla o evaluation do analytics: o evaluation só publica e responde rápido." |

---

## 3. O cluster por dentro (2 min) — terminal 1

**O que estamos fazendo:** mostrando que o kubectl está conectado ao EKS, que os nós estão saudáveis e que o Metrics Server e o Ingress estão instalados (pré-requisitos do HPA e da entrada de tráfego).

```bash
kubectl get nodes -o wide
```
"Os dois nós do node group estão Ready, em zonas diferentes da região us-east-1."

```bash
kubectl top nodes
```
"O `top` só funciona porque o Metrics Server está instalado. É ele que alimenta o HPA com o uso de CPU."

```bash
kubectl get pods -n kube-system
```
"Componentes do sistema: CoreDNS, kube-proxy, VPC CNI e o metrics-server."

```bash
kubectl get svc -n ingress-nginx
```
"O Nginx Ingress Controller foi instalado com Helm. Seu Service é do tipo LoadBalancer, e a AWS criou um Network Load Balancer, esse endereço `elb.amazonaws.com` é a porta de entrada pública."

---

## 4. Estado do ambiente e manifestos (3 min) — terminal 1

**O que estamos fazendo:** mostrando que os 5 serviços já estão publicados no EKS, sem derrubar nada. Percorremos cada tipo de recurso Kubernetes e os manifestos que o criaram.

```bash
kubectl get ns
```
"Um namespace por serviço: auth, flags, targeting, evaluation e analytics. Isso isola cada microserviço."

```bash
kubectl get pods -A
```
"Os pods de cada serviço Running, com 2 réplicas nos serviços de API. Os três jobs de inicialização dos bancos aparecem como Completed: eles criaram as tabelas nos RDS."

```bash
kubectl get svc -A
```
"Cada serviço tem um Service do tipo ClusterIP, acessível só dentro do cluster. Só o Ingress é exposto."

```bash
kubectl get ingress -A
```
"Os Ingress roteiam /auth, /flags, /targeting e /evaluate para o serviço certo, todos pelo mesmo Load Balancer."

```bash
kubectl get hpa -A
```
"Dois HPAs: evaluation (2 a 6 réplicas, meta de 70% de CPU) e analytics (1 a 5, meta de 50%)."

**Manifestos (mostre rapidamente; nunca o `secret.yaml`):**
```bash
cat k8s/evaluation-service/deployment.yaml
```
"Imagem vinda do ECR, variáveis do ConfigMap e do Secret, requests e limits de CPU e memória, e probes de readiness e liveness no /health."
```bash
cat k8s/evaluation-service/hpa.yaml
```
"A regra de escala por CPU."
```bash
kubectl get secret -n evaluation
```
"As credenciais ficam em Secrets do Kubernetes, não no código nem no repositório. Os valores não aparecem aqui."

---

## 5. Testes funcionais pelo Ingress (3 min) — terminal 1

**O que estamos fazendo:** validando o fluxo real passando pelo Load Balancer, como um cliente externo. Fazemos um teste de cada serviço e depois criamos uma flag nova.

```bash
curl -s http://$LB/auth/health
```
"Health check do auth-service, vindo pelo Ingress."

```bash
curl -s http://$LB/auth/validate -H "Authorization: Bearer $SERVICE_API_KEY"
```
"Valida a chave de API do evaluation-service. Ela está guardada no banco auth, que sobreviveu à recriação dos pods."

```bash
curl -s http://$LB/flags -H "Authorization: Bearer $SERVICE_API_KEY"
```
"Lista as flags no flag-service, que consulta o RDS de flags."

```bash
curl -s -X POST http://$LB/flags -H "Content-Type: application/json" -H "Authorization: Bearer $SERVICE_API_KEY" -d '{"name":"novo-checkout","description":"Novo fluxo de checkout","is_enabled":true}'
```
"Criando uma flag nova, 'novo-checkout'."

```bash
curl -s -X POST http://$LB/targeting/rules -H "Content-Type: application/json" -H "Authorization: Bearer $SERVICE_API_KEY" -d '{"flag_name":"novo-checkout","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}'
```
"E uma regra de segmentação: a flag fica ligada para 50% dos usuários, decidido de forma determinística por um hash do user_id."

```bash
curl -s "http://$LB/evaluate?user_id=u1&flag_name=novo-checkout"
curl -s "http://$LB/evaluate?user_id=u5&flag_name=novo-checkout"
```
"O evaluation-service consulta flag e regra, guarda no Redis e responde. Dois usuários podem ter resultados diferentes, por causa dos 50%. Cada avaliação também publica um evento na fila SQS."

```bash
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --query Count --output text
kubectl logs -n analytics deploy/analytics-service --tail=5
```
"O analytics-service consumiu os eventos da fila e gravou no DynamoDB. Aqui está o contador e os logs 'salvo no DynamoDB'. Isso fecha o fluxo: evaluate, SQS, analytics, DynamoDB."

---

## 6. Escalabilidade com HPA (5 min)

**O que estamos fazendo:** gerando carga pesada no endpoint `/evaluate` para que a CPU suba e o Kubernetes crie mais pods automaticamente (HPA). Também mostramos o analytics escalando, porque cada requisição vira uma mensagem na fila.

**Terminal 2:**
```bash
watch -n 5 kubectl get hpa -A
```
"Aqui vemos os dois HPAs: o do evaluation com meta de 70% de CPU e o do analytics com meta de 50%."

**Terminal 3:**
```bash
watch -n 5 kubectl get pods -n evaluation
```
"E aqui os pods do evaluation. Agora são 2, que é o mínimo."

**Terminal 1 (carga de 2 minutos, 100 conexões simultâneas):**
```bash
hey -z 2m -c 100 "http://$LB/evaluate?user_id=u1&flag_name=novo-checkout"
```
"Estou usando a ferramenta `hey` para enviar milhares de requisições por segundo ao Load Balancer."

*Aponte os terminais 2 e 3:* a CPU sobe acima de 70%, as réplicas do evaluation sobem de 2 até 6, e o analytics também escala (até 5).

Quando o `hey` terminar, mostre o resumo (`Requests/sec`, `Status code distribution [200]`) e:
```bash
aws sqs get-queue-attributes --queue-url "$AWS_SQS_URL" --attribute-names ApproximateNumberOfMessages --query Attributes --output json
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --query Count --output text
```
"A carga encheu a fila: essas são as mensagens esperando. O analytics escalou e está drenando a fila, e a contagem do DynamoDB cresce. Quando a carga termina, o HPA reduz as réplicas gradualmente, leva uns 5 minutos por causa da janela de estabilização."

---

## 7. Explicações e desafios (3 min) — só fala

**HPA em vez de KEDA:**
"A proposta ideal para o analytics seria escalar pela profundidade da fila com KEDA. Mas no AWS Academy só existe a LabRole e não é possível criar roles IAM nem usar IRSA, que o KEDA precisa para ler a fila SQS. Por isso usei o HPA por CPU: com a fila cheia, o analytics processa mais, a CPU sobe e o HPA escala. É um workaround, e os pods acessam a AWS pelo role do nó."

**Por que cada banco:**
- "RDS PostgreSQL para flags, regras e chaves: dados relacionais e transacionais, com schema definido."
- "ElastiCache Redis no evaluation: leitura de baixíssima latência no caminho quente, com TTL, evitando bater no RDS a cada requisição."
- "DynamoDB para os eventos: alto volume de escrita, sem schema fixo e sem joins."

**Desafios que resolvi:**
1. "Na minha conta pessoal, o plano gratuito bloqueava instâncias t3.medium e os nós nunca subiam. Migrei para o AWS Academy."
2. "O cluster nasceu com o EKS Auto Mode ligado e criou um acesso do tipo errado para a LabRole. Os nós não conseguiam se registrar. Recriei o acesso como EC2_LINUX."
3. "Sem IRSA, os pods não achavam credenciais. O IMDS tinha hop limit 1, bloqueando os contêineres. Subi para 2."
4. "O código-fonte original tinha bugs: imports não usados em Go, go.mod inválido, dependências incompatíveis. Corrigi para compilar."

---

## 8. Fechamento (30 s)

"Resumindo: cinco serviços containerizados com multi-stage build, imagens no ECR, rodando em um EKS com Ingress, usando RDS, ElastiCache, DynamoDB e SQS, com autoscaling por HPA validado sob carga. O repositório e o relatório de entrega estão no link da entrega. Obrigado."

---

## Checklist rápido antes de gravar
- [ ] Os 2 nós `Ready` e os 5 serviços `Running`.
- [ ] `echo $LB` mostra o endereço (nos 3 terminais).
- [ ] `curl http://$LB/auth/health` responde `{"status":"ok"}`.
- [ ] Terminal limpo (`clear`), sem variáveis secretas visíveis.
- [ ] HPA do evaluation de volta a 2 réplicas, para o scale-up ficar visível.
- [ ] Aba do Console aberta em cada serviço.
