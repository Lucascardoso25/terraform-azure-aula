# terraform-azure-aula

Aplicação containerizada com **Docker**, com infraestrutura criada por **Terraform** e deploy automático via **GitHub Actions** em uma **VM Linux na Azure**.

Projeto da disciplina **Integração e Entrega Contínua (DevOps)**.

## Visão geral

O repositório tem dois workflows independentes:

| Workflow | Arquivo | Quando roda | O que faz |
|----------|---------|-------------|-----------|
| Terraform Azure | `.github/workflows/main.yml` | Manual (`workflow_dispatch`) | Cria a VM e a rede na Azure |
| Build e Deploy Docker II | `.github/workflows/pipeline.yml` | Push na `main` ou manual | Builda a imagem, publica no Docker Hub e implanta na VM |

```
Terraform (manual)  ->  VM Azure com Docker
                              ^
push na main -> GitHub Actions -> Docker Hub -> SSH na VM -> container no ar
```

## Estrutura do projeto

```
terraform-azure-aula/
├── .github/
│   └── workflows/
│       ├── main.yml        # criação da infraestrutura (Terraform)
│       └── pipeline.yml    # build e deploy da aplicação
├── app/
│   └── index.html          # aplicação (site estático)
├── dockerfile              # imagem Docker (nginx)
├── main.tf                 # infraestrutura Azure
├── .dockerignore
├── .gitignore
└── README.md
```

## Tecnologias

- Docker e nginx
- GitHub Actions
- Docker Hub
- Terraform (provider `azurerm ~> 4.0`)
- Azure (VM Ubuntu 22.04)

## Como rodar localmente

Pré-requisito: [Docker](https://www.docker.com/) instalado.

```bash
docker build -t app-docker-aula .
docker run -d --name app-docker-aula -p 8080:80 app-docker-aula
```

Acesse em `http://localhost:8080`. Para parar e remover:

```bash
docker rm -f app-docker-aula
```

## Infraestrutura (Terraform)

O `main.tf` cria na Azure:

| Recurso | Nome | Detalhe |
|---------|------|---------|
| Resource group | `rg-terraform-aula` | Região `southafricanorth` |
| Rede virtual / sub-rede | `terraform-vnet` / `default` | `10.10.0.0/16` e `10.10.1.0/24` |
| Network security group | `terraform-nsg` | Libera as portas **80** (HTTP) e **22** (SSH) |
| IP público | `terraform-ip` | Estático, SKU Standard |
| VM Linux | `terraform-linux-vm` | Ubuntu 22.04, tamanho `Standard_B2ats_v2`, usuário `azureuser` |

A VM só aceita login por chave SSH (senha desabilitada). O Docker é instalado automaticamente pelo **cloud-init** na criação da VM, o que leva alguns minutos depois que ela sobe.

Outputs exibidos ao final do `apply`: `resource_group`, `nome_vm`, `ip_publico`, `tamanho_vm` e `comando_ssh`.

### Autenticação na Azure

O workflow usa **OIDC** (sem senha guardada). É preciso ter um App Registration na Azure com credencial federada apontando para este repositório e permissão no escopo da assinatura.

### Estado do Terraform

Por padrão **não há backend remoto**: o estado fica só dentro da execução do workflow. Por isso:

- rode o workflow `Terraform Azure` **uma vez só**;
- uma segunda execução tentará recriar tudo e falhará com erro de "já existe".

Para repetir execuções, configure o backend `azurerm` (bloco comentado no `main.tf`) usando um Storage Account.

### Remover a infraestrutura

Como não há estado remoto, a forma mais simples de apagar tudo (e parar de gastar crédito) é excluir o resource group `rg-terraform-aula` no portal da Azure.

## Pipeline de deploy

### Jobs

| Job | O que faz |
|-----|-----------|
| `build` | Login no Docker Hub, build da imagem e push com a tag `latest` |
| `deploy` | Acessa a VM por SSH, espera o Docker ficar disponível, faz `docker pull` e sobe o container na porta 80 |

### Secrets necessários

Configure em **Settings > Secrets and variables > Actions**:

| Secret | Usado em | Descrição |
|--------|----------|-----------|
| `AZURE_CLIENT_ID` | Terraform | ID do App Registration (OIDC) |
| `AZURE_TENANT_ID` | Terraform | ID do tenant da Azure |
| `AZURE_SUBSCRIPTION_ID` | Terraform | ID da assinatura |
| `SSH_PUBLIC_KEY` | Terraform | Chave **pública** SSH, instalada na VM |
| `DOCKERHUB_USERNAME` | Pipeline | Usuário do Docker Hub |
| `DOCKERHUB_TOKEN` | Pipeline | Token de acesso do Docker Hub |
| `AZURE_VM_HOST` | Pipeline | IP público da VM (output `ip_publico`) |
| `AZURE_VM_USER` | Pipeline | `azureuser` |
| `AZURE_VM_SSH_KEY` | Pipeline | Chave **privada** SSH (par da pública acima) |

### Gerando o par de chaves SSH

```bash
ssh-keygen -t ed25519 -f azure_vm_key -N ""
```

- Conteúdo de `azure_vm_key.pub` vai em `SSH_PUBLIC_KEY`.
- Conteúdo de `azure_vm_key` (privada) vai em `AZURE_VM_SSH_KEY`.
- Não versione esses arquivos (o `.gitignore` já ignora).

## Passo a passo completo

1. Crie os secrets do Terraform (`AZURE_*` e `SSH_PUBLIC_KEY`).
2. Na aba **Actions**, rode manualmente o workflow **Terraform Azure**.
3. Copie o `ip_publico` do final do log e crie os secrets `AZURE_VM_HOST`, `AZURE_VM_USER` e `AZURE_VM_SSH_KEY`.
4. Crie `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`.
5. Faça um push na `main` (ou rode **Build e Deploy Docker II** manualmente).
6. Acesse `http://<IP_DA_VM>` no navegador.

## Troubleshooting

- **Login no Docker Hub falha:** confira `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`.
- **Deploy falha com erro de SSH:** confira `AZURE_VM_HOST`, `AZURE_VM_USER` e se `AZURE_VM_SSH_KEY` é a privada correspondente à pública usada no Terraform.
- **`docker: command not found`:** o cloud-init ainda não terminou. O deploy já espera, mas se estourar o tempo, rode de novo após alguns minutos.
- **Terraform diz que o recurso já existe:** o estado não foi mantido entre execuções (veja "Estado do Terraform").
- **Site não abre:** rode `docker ps` na VM e confira se a porta 80 está liberada no NSG.
- **Logs do container:** `docker logs app-docker-aula`.

## Autor

Preencha com seu nome e turma (FATEC).
