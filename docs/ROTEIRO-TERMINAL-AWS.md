# Roteiro do terminal AWS — 8 min

Cobre o que o enunciado pede: Pods rodando, Ingress com curl no Load Balancer, carga no evaluation com HPA,
envio manual de mensagens à SQS, HPA do analytics, dados no DynamoDB, justificativa do HPA e diferença dos 3 data stores.
Nenhum comando contém `;` ou `<>`.

## Antes de gravar (fora da câmera)
**Atenção:** o `scan --select COUNT` pagina de 1 em 1 MB e imprime uma contagem por página. O `awk` no fim soma tudo e mostra um número só.
Se você ensaiou o `sqs.sh` ou o `hey`, espere ~5 min até `kubectl get hpa -A` mostrar evaluation com 2 réplicas e analytics com 1.

Terminal principal já com `AWS_PROFILE`, `LB`, `SERVICE_API_KEY` e `AWS_SQS_URL` carregados, `/tmp/sqs.sh` criado.
Confira: evaluation com **2** réplicas e analytics com **1** (`kubectl get hpa -A`).
Tela dividida em 3 painéis:
- Painel 2: `watch -n 5 kubectl get hpa -A`
- Painel 3: `watch -n 5 kubectl get pods -A`
- Painel 1 (principal): os comandos abaixo.
Dê `clear` e inicie o cronômetro. **Nunca mostrar:** `echo $SERVICE_API_KEY`, `env`, `cat aws/outputs.env`, `get secret -o yaml`.

---

## 0:00 – 0:30 · Abertura
**Fale:** "Agora vou mostrar o ToggleMaster rodando na AWS. São 5 microsserviços no EKS, atrás de um Nginx Ingress, usando RDS, ElastiCache, DynamoDB e SQS."

## 0:30 – 1:30 · O cluster e os Pods
**O que estamos fazendo:** provando que o cluster existe e que os 5 serviços são Pods.
```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
kubectl get hpa -A
```
**Fale:** "Dois nós Ready no EKS. Cada microsserviço tem seu namespace e roda com 2 réplicas, menos o analytics, que começa com 1. O Ingress expõe tudo por um Load Balancer da AWS. E aqui estão os dois HPAs: evaluation de 2 a 6 réplicas com meta de 70% de CPU, e analytics de 1 a 5 com meta de 50%."

## 1:30 – 2:30 · Nginx Ingress funcionando
**O que estamos fazendo:** chamando a URL do Load Balancer, como um cliente externo.
```bash
echo $LB
curl -s http://$LB/auth/health
curl -s http://$LB/auth/validate -H "Authorization: Bearer $SERVICE_API_KEY"
curl -s http://$LB/flags -H "Authorization: Bearer $SERVICE_API_KEY"
curl -s "http://$LB/evaluate?user_id=u1&flag_name=enable-new-dashboard"
curl -s "http://$LB/evaluate?user_id=u5&flag_name=enable-new-dashboard"
```
**Fale:** "Esta é a URL do Network Load Balancer. O Ingress roteia pelo caminho: /auth para o auth-service, /flags para o flag-service e /evaluate para o evaluation. O evaluation consulta flag e regra, usa o Redis como cache e devolve true ou false. Cada avaliação também publica um evento na fila SQS."

## 2:30 – 3:15 · Estado inicial dos dados
**O que estamos fazendo:** guardando o "antes" para comparar com o "depois" da carga.
```bash
aws sqs get-queue-attributes --queue-url "$AWS_SQS_URL" --attribute-names ApproximateNumberOfMessages --query Attributes --output json
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --query Count --output text | awk '{s+=$1} END {print s}'
```
**Fale:** "A fila está praticamente vazia e a tabela do DynamoDB tem esta quantidade de eventos. Vou anotar para comparar."

## 3:15 – 5:00 · Envio manual de mensagens à SQS + HPA do analytics
**O que estamos fazendo:** enchendo a fila na mão (5.000 mensagens) para o analytics-service precisar escalar.
```bash
bash /tmp/sqs.sh
```
*(Aponte os painéis 2 e 3: a CPU do analytics sobe acima de 50% e as réplicas aumentam, de 1 até 5.)*

**Fale durante o envio e a espera (justificativa do HPA):**
"Estou enviando 5.000 mensagens direto para a fila SQS. O ideal para o analytics seria o KEDA, escalando pelo tamanho da fila. Mas no AWS Academy só existe a LabRole, e não dá para criar roles IAM nem usar IRSA, que o KEDA precisa para ler a fila. Então usei o HPA por CPU: com a fila cheia, o analytics processa mais mensagens, a CPU sobe e o HPA cria mais Pods. Como o analytics gasta pouca CPU em repouso, usei requests de 50 millicores e alvo de 50% para o HPA reagir. Não é tão preciso quanto escalar pela fila, mas funciona para esse cenário."

## 5:00 – 7:00 · Carga no evaluation + HPA
**O que estamos fazendo:** gerando tráfego pesado no `/evaluate` para a CPU subir e o HPA criar réplicas.
```bash
hey -z 90s -c 100 "http://$LB/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```
*(Aponte o painel 2: a CPU do evaluation passa de 70% e as réplicas sobem de 2 para até 6. No resumo do `hey`, mostre `Requests/sec` e `[200]`.)*

**Fale durante a carga (os 3 data stores):**
"Enquanto isso, a diferença entre os três bancos. O RDS PostgreSQL guarda dados relacionais e transacionais: chaves de API, flags e regras, cada microsserviço com o seu banco. O ElastiCache Redis é um cache em memória de baixa latência, usado no caminho quente do evaluation para não consultar o banco a cada requisição. E o DynamoDB é NoSQL, ideal para o alto volume de escrita dos eventos de analytics, sem esquema fixo e sem joins."

## 7:00 – 8:00 · Resultado e encerramento
**O que estamos fazendo:** mostrando o efeito da carga e fechando.
```bash
kubectl get hpa -A
aws sqs get-queue-attributes --queue-url "$AWS_SQS_URL" --attribute-names ApproximateNumberOfMessages --query Attributes --output json
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --query Count --output text | awk '{s+=$1} END {print s}'
```
**Fale:** "O evaluation escalou até 6 réplicas, o analytics também escalou para drenar a fila, e a tabela do DynamoDB cresceu em relação ao valor inicial: aqui estão os eventos gravados." *(Se quiser, mostre os itens no Console: DynamoDB → Tabelas → ToggleMasterAnalytics → Explorar itens.)*

**Desafios (30 s):** "Os principais desafios foram as limitações da LabRole: sem IRSA os Pods precisaram usar o role do nó, e tive que ajustar o hop limit do metadados da instância. O cluster também nasceu com o EKS Auto Mode ligado, que criou um acesso errado para os nós, e precisei corrigir. E o código original tinha bugs de build que corrigi. Obrigado."

---

## Plano B se o tempo apertar
- Passe de 8:30? Na edição, acelere em 4× (sem áudio) o `sqs.sh` e a maior parte do `hey`.
- A carga do `hey` pode ser `-z 60s` se o HPA já estiver subindo bem.
- Se o analytics não passar de 50% de CPU com o `sqs.sh`, rode o `hey` logo em seguida: cada requisição também vira mensagem na fila.

## Checklist
- [ ] evaluation com 2 réplicas e analytics com 1 antes de começar.
- [ ] Painéis do HPA e dos pods visíveis durante o envio e a carga.
- [ ] Valor inicial do DynamoDB anotado.
- [ ] Nenhum segredo na tela.
