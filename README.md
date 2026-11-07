# terraform-azure-aula

Infraestrutura na **Azure** criada com **Terraform** e aplicações implantadas com **Docker**, **Docker Compose** e **GitHub Actions**.

Projeto da disciplina **Integração e Entrega Contínua (DevOps)**.

## Visão geral

| Workflow | Arquivo | Quando roda | O que faz |
|----------|---------|-------------|-----------|
| Terraform Azure | `.github/workflows/main.yml` | Manual | Cria a VM e a rede na Azure |
| Build e Deploy Docker II | `.github/workflows/pipeline.yml` | Push em `app/**` ou manual | Site simples (nginx): build, push no Docker Hub e deploy na VM |
| Deploy Compose (site + banco) | `.github/workflows/deploy-compose.yml` | Push em `site-db/**` ou manual | Site com PostgreSQL: build, push, cópia do Compose e deploy na VM |

Os dois deploys passam por um **estágio de aprovação** (veja abaixo).

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

Pasta `app/` + `dockerfile` na raiz. A pipeline `pipeline.yml` builda a imagem `app-docker-aula`, publica no Docker Hub e, após a aprovação, roda o container na porta 80 da VM.

Teste local:

```bash
docker build -t app-docker-aula .
docker run -d --name app-docker-aula -p 8080:80 app-docker-aula
```

## 2. Site com banco de dados (Docker Compose)

A pasta `site-db/` tem uma aplicação **"Mural de recados"**: página web + API em Node/Express + banco **PostgreSQL**, sobem juntos com Docker Compose.

| Serviço | Imagem | Detalhes |
|---------|--------|----------|
| `web` | `<usuario>/site-db-web:latest` | Node 20, porta interna 3000, publicada na porta 80 da VM |
| `db` | `postgres:16-alpine` | Dados no volume `db_data`, sem porta exposta na internet, com healthcheck |

O `web` só inicia depois que o banco estiver saudável (`depends_on` com `service_healthy`), e a aplicação ainda tenta reconectar sozinha caso o banco demore.

Endpoints: `GET /health`, `GET /api/recados`, `POST /api/recados`.

Teste local (precisa de Docker com Compose):

```bash
cd site-db
cp .env.example .env
docker compose up --build
```

Acesse `http://localhost:8080`.

Como a porta 80 da VM é única, o deploy do Compose remove o container do site simples antes de subir, e o deploy do site simples derruba o Compose antes de subir (os dados do banco ficam preservados no volume).

## 3. Estágio de aprovação

Os jobs de deploy usam `environment: producao`. Antes de rodar, o GitHub pausa o job e espera um revisor aprovar.

Para configurar:

1. Repositório > **Settings > Environments > New environment**, com o nome `producao`.
2. Marque **Required reviewers** e adicione seu usuário (ou o do professor).
3. Salve.

Quando a pipeline chegar no deploy, aparece o botão **Review deployments**. Marque `producao`, clique em **Approve and deploy**, e o job continua.

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
| `POSTGRES_PASSWORD` | Compose | Senha do banco (use letras e números, sem aspas) |

## Infraestrutura (Terraform)

O `main.tf` cria:

| Recurso | Nome | Detalhe |
|---------|------|---------|
| Resource group | `rg-terraform-aula` | Região `southafricanorth` |
| Rede virtual / sub-rede | `terraform-vnet` / `default` | `10.10.0.0/16` e `10.10.1.0/24` |
| Network security group | `terraform-nsg` | Libera as portas **80** e **22** |
| IP público | `terraform-ip` | Estático |
| VM Linux | `terraform-linux-vm` | Ubuntu 22.04, `Standard_B2ats_v2`, usuário `azureuser` |

Docker e Docker Compose são instalados pelo cloud-init na criação da VM. A VM só aceita login por chave SSH.

Sem backend remoto, rode o workflow **Terraform Azure** uma vez só (um segundo `apply` tenta recriar tudo). Para apagar tudo, exclua o resource group no portal da Azure.

## Passo a passo

1. Crie os secrets (tabela acima) e o environment `producao` com revisor.
2. Rode o workflow **Terraform Azure** (se a VM ainda não existir) e pegue o IP.
3. Faça push em `site-db/**` (ou rode **Deploy Compose** manualmente).
4. Quando o job `deploy` pausar, aprove em **Review deployments**.
5. Acesse `http://<IP_DA_VM>`: a página "Mural de recados" deve mostrar "Banco de dados conectado".

## Troubleshooting

- **Job de deploy parado em "Waiting":** falta aprovar em **Review deployments**.
- **Login no Docker Hub falha:** confira `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`.
- **Push falha com "insufficient scopes":** gere um token com permissão Read & Write.
- **`missing server host`:** o secret `AZURE_VM_HOST` não existe ou está vazio.
- **Erro de SSH (`unable to authenticate`):** `AZURE_VM_SSH_KEY` precisa ser a privada do par da pública que está na VM.
- **Porta 80 em uso:** só um dos sites roda por vez na porta 80; o próprio deploy do outro libera a porta.
- **Ver logs na VM:** `docker compose -f ~/site-db/docker-compose.yml logs` (Compose) ou `docker logs app-docker-aula` (site simples).
- **Ver os containers:** `docker ps`.

## Autor

Preencha com seu nome e turma (FATEC).
