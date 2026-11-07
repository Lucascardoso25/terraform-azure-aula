# terraform-azure-aula

Infraestrutura na **Azure** criada com **Terraform** e aplicações implantadas com **Docker**, **Docker Compose** e **GitHub Actions**, com estágio de aprovação antes do deploy.

Projeto da disciplina **Integração e Entrega Contínua (DevOps)**, FATEC, curso de Desenvolvimento de Software Multiplataforma (DSM).

## Requisitos da atividade "CD com Docker e Docker Compose"

| Requisito | Onde está |
|-----------|-----------|
| Deploy de um site simples no servidor da Azure | `app/` + `dockerfile` + `.github/workflows/pipeline.yml` |
| Deploy de um site com página web + banco de dados via Docker Compose | `site-db/` + `.github/workflows/deploy-compose.yml` |
| Estágio de aprovação no deploy | `environment: producao` nos dois jobs de deploy |

## Endereços (ambiente da aula)

| Aplicação | Endereço |
|-----------|----------|
| Site simples (nginx) | `http://20.164.210.248` |
| Site com banco (Mural de recados) | `http://20.164.210.248:8081` |
| Verificação de saúde (site + banco) | `http://20.164.210.248:8081/health` |

O IP é estático enquanto a VM existir. Se o resource group for apagado e a VM recriada, o IP muda e o secret `AZURE_VM_HOST` precisa ser atualizado.

## Visão geral

| Workflow | Arquivo | Quando roda | O que faz |
|----------|---------|-------------|-----------|
| Terraform Azure | `.github/workflows/main.yml` | Manual | Cria a VM e a rede na Azure |
| Build e Deploy Docker II | `.github/workflows/pipeline.yml` | Push em `app/**`, `dockerfile` ou manual | Site simples: build, push no Docker Hub e deploy na VM |
| Deploy Compose (site + banco) | `.github/workflows/deploy-compose.yml` | Push em `site-db/**` ou manual | Site com PostgreSQL: build, push, cópia do Compose e deploy na VM |

```
push -> build (imagem no Docker Hub) -> [aprovação manual] -> deploy na VM Azure via SSH
```

## Estrutura do projeto

```
terraform-azure-aula/
├── .github/workflows/
│   ├── main.yml              # Terraform (cria a VM)
│   ├── pipeline.yml          # deploy do site simples
│   └── deploy-compose.yml    # deploy do site + banco
├── app/
│   └── index.html            # site simples (nginx)
├── site-db/
│   ├── docker-compose.yml    # web + PostgreSQL
│   ├── .env.example          # variáveis para teste local
│   └── web/
│       ├── Dockerfile
│       ├── package.json
│       ├── server.js         # API Node/Express
│       └── public/index.html # página "Mural de recados"
├── dockerfile                # imagem do site simples
├── main.tf                   # infraestrutura Azure
└── README.md
```

## 1. Site simples (nginx)

Pasta `app/` + `dockerfile` na raiz. O `pipeline.yml` builda a imagem `app-docker-aula`, publica no Docker Hub e, após a aprovação, roda o container `app-docker-aula` na porta **80** da VM.

Teste local:

```bash
docker build -t app-docker-aula .
docker run -d --name app-docker-aula -p 8080:80 app-docker-aula
```

Se a porta 8080 já estiver em uso no seu computador, troque por outra (por exemplo `-p 8082:80`).

## 2. Site com banco de dados (Docker Compose)

A pasta `site-db/` tem a aplicação **"Mural de recados"**: página web + API em Node/Express + banco **PostgreSQL**, que sobem juntos com Docker Compose.

| Serviço | Imagem | Detalhes |
|---------|--------|----------|
| `web` | `<usuario>/site-db-web:latest` | Node 20, porta interna 3000, publicada na porta **8081** da VM |
| `db` | `postgres:16-alpine` | Dados no volume `db_data`, sem porta exposta na internet, com healthcheck |

O `web` só inicia depois que o banco estiver saudável (`depends_on` com `service_healthy`), e a aplicação ainda tenta reconectar sozinha caso o banco demore.

Endpoints: `GET /health`, `GET /api/recados`, `POST /api/recados`.

### Como o deploy funciona

1. O job `build` gera a imagem `site-db-web` e publica no Docker Hub.
2. Após a aprovação, o job `deploy` copia o `docker-compose.yml` para `~/site-db` na VM.
3. Por SSH, grava o `.env` (senha do banco, usuário do Docker Hub e `WEB_PORT=8081`), roda `docker compose pull` e `docker compose up -d`.
4. O último passo chama `/health` na porta 8081 e falha se o site ou o banco não responderem.

Teste local (precisa de Docker com Compose):

```bash
cd site-db
cp .env.example .env
docker compose up --build
```

Acesse `http://localhost:8080` (porta definida em `WEB_PORT` no `.env`).

## 3. Estágio de aprovação

Os jobs de deploy usam `environment: producao`. Antes de rodar, o GitHub pausa o job e espera um revisor aprovar.

Configuração:

1. Repositório > **Settings > Environments > New environment**, com o nome `producao`.
2. Marque **Required reviewers** e adicione os revisores.
3. Salve.

Quando a pipeline chega no deploy, aparece o botão **Review deployments**: marque `producao` e clique em **Approve and deploy**.

> Em repositórios privados de conta gratuita, a opção de revisores obrigatórios pode não aparecer. Nesse caso, deixe o repositório público (os secrets não ficam no código).

## Secrets necessários

Configure em **Settings > Secrets and variables > Actions > Repository secrets**:

| Secret | Usado em | Descrição |
|--------|----------|-----------|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Terraform | Identificam a conta Azure (OIDC) |
| `SSH_PUBLIC_KEY` | Terraform | Chave **pública** SSH instalada na VM |
| `DOCKERHUB_USERNAME` | Pipelines | Usuário do Docker Hub |
| `DOCKERHUB_TOKEN` | Pipelines | Token do Docker Hub com permissão **Read & Write** |
| `AZURE_VM_HOST` | Pipelines | IP público da VM |
| `AZURE_VM_USER` | Pipelines | `azureuser` |
| `AZURE_VM_SSH_KEY` | Pipelines | Chave **privada** SSH (par da pública acima) |
| `POSTGRES_PASSWORD` | Compose | Senha do banco (letras e números, sem aspas) |

## Infraestrutura (Terraform)

O `main.tf` cria:

| Recurso | Nome | Detalhe |
|---------|------|---------|
| Resource group | `rg-terraform-aula` | Região `southafricanorth` |
| Rede virtual / sub-rede | `terraform-vnet` / `default` | `10.10.0.0/16` e `10.10.1.0/24` |
| Network security group | `terraform-nsg` | Libera as portas **80** (HTTP), **8081** (site com banco) e **22** (SSH) |
| IP público | `terraform-ip` | Estático |
| VM Linux | `terraform-linux-vm` | Ubuntu 22.04, `Standard_B2ats_v2`, usuário `azureuser` |

Docker e Docker Compose são instalados pelo cloud-init na criação da VM, e o login é só por chave SSH.

Sem backend remoto, rode o workflow **Terraform Azure** uma vez só (um segundo `apply` tenta recriar tudo). Para apagar tudo, exclua o resource group no portal da Azure.

### Chave SSH

Gere um par exclusivo para o deploy:

```bash
ssh-keygen -t ed25519 -f azure_deploy_key
```

A pública (`.pub`) vai no secret `SSH_PUBLIC_KEY` e em `~/.ssh/authorized_keys` da VM. A privada vai **somente** no secret `AZURE_VM_SSH_KEY`. Nunca compartilhe a privada em chats, prints ou no repositório (o `.gitignore` já ignora esses arquivos). Se ela vazar, gere um par novo e troque a pública na VM.

## Passo a passo

1. Crie os secrets (tabela acima) e o environment `producao` com revisor.
2. Rode o workflow **Terraform Azure** (se a VM ainda não existir) e pegue o IP.
3. Faça push em `site-db/**` (ou rode **Deploy Compose** manualmente).
4. Quando o job `deploy` pausar, aprove em **Review deployments**.
5. Acesse `http://<IP_DA_VM>:8081`: a página "Mural de recados" deve mostrar "Banco de dados conectado".

## Troubleshooting

- **Job de deploy parado em "Waiting":** falta aprovar em **Review deployments**.
- **Login no Docker Hub falha (`Username and password required`):** os secrets `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN` não existem ou estão com nome diferente.
- **Push falha com `insufficient scopes`:** gere um token do Docker Hub com permissão Read & Write.
- **`missing server host`:** o secret `AZURE_VM_HOST` não existe ou está vazio.
- **Erro de SSH (`unable to authenticate`):** `AZURE_VM_SSH_KEY` precisa ser a privada do par da pública que está na VM.
- **`container site-db-postgres is unhealthy`:** quase sempre o secret `POSTGRES_PASSWORD` está vazio ou ausente. Confira com `docker logs site-db-postgres` (a mensagem é `superuser password is not specified`). Corrija o secret, rode o deploy de novo e, se sobrou volume de uma tentativa anterior, rode `docker compose down -v` na VM antes.
- **Site com banco não abre:** use `http://<IP_DA_VM>:8081` (com a porta) e confira se a regra de entrada da porta 8081 existe no `terraform-nsg`.
- **`port is already allocated` no teste local:** a porta já está em uso no seu computador. Troque a porta no `docker run` ou o `WEB_PORT` no `.env`.
- **Logs na VM:** `docker compose -f ~/site-db/docker-compose.yml logs` (Compose) ou `docker logs app-docker-aula` (site simples).
- **Containers em execução:** `docker ps`.

## Autor
Lucas Aires Cardoso