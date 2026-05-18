# Guia do Administrador

Este documento é para o professor ou monitor responsável pelo servidor. Cobre instalação, configuração inicial, operação diária e resolução de problemas.

---

## Visão geral da responsabilidade

| Quem | Faz o quê |
|------|-----------|
| **Admin (você)** | Instalar dependências, configurar servidor, preencher `.env`, gerenciar Deploy Keys, iniciar watcher |
| **Grupos** | Configurar os próprios projetos (Dockerfile, vite.config, URL da API) e fazer push na branch `deploy` |

---

## Pré-requisitos de hardware e software

**Hardware mínimo recomendado:**
- 4 GB RAM (8+ recomendado para 6 projetos simultâneos)
- 50 GB de disco
- Ubuntu Server 20.04 LTS ou mais recente

**Software instalado pelo bootstrap automaticamente:**
- Docker Engine >= 20.10
- Docker Compose v2 (plugin `docker compose`)
- Node.js >= 18
- Git
- openssh-client (para geração da chave SSH)

---

## Passo 1 — Instalar tudo com o bootstrap

Em um servidor Ubuntu limpo, execute como usuário com sudo (não como root):

```bash
curl -fsSL https://raw.githubusercontent.com/hknorst/es-builder/main/bootstrap.sh | bash
```

O script faz tudo automaticamente:
1. Instala Docker, Docker Compose v2, Node.js e openssh-client
2. Gera o par de chaves SSH de deploy em `~/.ssh/es-builder_ed25519`
3. Configura `~/.ssh/config` para usar essa chave no GitHub
4. Adiciona seu usuário ao grupo `docker`
5. Clona o repositório em `~/es-builder`
6. Exibe a chave pública na tela e salva em `~/es-builder/deploy-key.pub`

Ao terminar, **faça logout e login novamente** para o grupo `docker` entrar em vigor:

```bash
exit
# reconecte via SSH
```

---

## Passo 2 — Cadastrar a chave de deploy no GitHub

O bootstrap já gerou e exibiu a chave pública ao final. Para vê-la novamente:

```bash
cat ~/es-builder/deploy-key.pub
```

Cadastre essa chave em **cada repositório dos grupos** (somente leitura — o servidor só precisa clonar e fazer fetch):

```
Repositório → Settings → Deploy Keys → Add deploy key
  Title: es-builder-server
  Key: (colar o conteúdo do comando acima)
  Allow write access: NÃO marcar
```

Repita para todos os 6 repositórios: portal, projeto-a, projeto-b, projeto-c, projeto-d, projeto-e.

**Testar a conexão após cadastrar:**

```bash
ssh -T git@github.com
# Resposta esperada: Hi <usuario>! You've successfully authenticated...
```

---

## Passo 3 — Configurar as URLs dos repositórios

Edite o arquivo `scripts/setup.sh` e preencha as URLs SSH dos repositórios de cada grupo:

```bash
cd ~/es-builder
nano scripts/setup.sh
```

Localize o bloco no topo do arquivo e substitua:

```bash
REPO_PORTAL="git@github.com:nome-da-org/portal.git"
REPO_PROJETO_A="git@github.com:nome-da-org/projeto-a.git"
REPO_PROJETO_B="git@github.com:nome-da-org/projeto-b.git"
REPO_PROJETO_C="git@github.com:nome-da-org/projeto-c.git"
REPO_PROJETO_D="git@github.com:nome-da-org/projeto-d.git"
REPO_PROJETO_E="git@github.com:nome-da-org/projeto-e.git"
```

---

## Passo 4 — Executar o setup

```bash
cd ~/es-builder
bash scripts/setup.sh
```

O script vai:
1. Clonar todos os repositórios dos grupos em `projects/`
2. Criar os arquivos `envs/projeto-x.env` com as variáveis comentadas
3. Subir o Nginx (e criar a rede Docker `orq-net`)

---

## Passo 5 — Preencher as variáveis de ambiente

Cada projeto tem um arquivo `envs/projeto-x.env`. Preencha com os grupos durante a aula ou defina valores padrão para teste:

```bash
nano envs/portal.env
nano envs/projeto-a.env
nano envs/projeto-b.env
nano envs/projeto-c.env
nano envs/projeto-d.env
nano envs/projeto-e.env
```

**Variáveis que precisam ser preenchidas em todos os arquivos:**

```bash
# Igual em TODOS os projetos — o portal emite, os outros validam
JWT_SECRET=uma-chave-longa-e-aleatoria-gerada-por-voce

# Específico de cada projeto (trocar projeto-x pelo nome real)
POSTGRES_USER=appuser
POSTGRES_PASSWORD=senha-segura
POSTGRES_DB=projeto_x_db
DATABASE_URL=postgresql://appuser:senha-segura@projeto-x-db:5432/projeto_x_db
```

**Gerar um JWT_SECRET seguro:**

```bash
openssl rand -hex 32
```

> Use o mesmo valor gerado para todos os projetos.

---

## Passo 6 — Iniciar o watcher

O watcher monitora todos os repositórios a cada 60 segundos e dispara o deploy automaticamente quando detecta novos commits na branch `deploy`.

**Em foreground** (para ver os logs na tela, útil no início):

```bash
node scripts/watcher.js
```

**Em background** (para produção):

```bash
nohup node scripts/watcher.js >> logs/watcher.log 2>&1 &
echo $! > watcher.pid
echo "Watcher iniciado com PID $(cat watcher.pid)"
```

**Verificar se está rodando:**

```bash
ps aux | grep watcher.js
```

**Parar o watcher:**

```bash
kill $(cat watcher.pid)
```

---

## Proteger a branch deploy nos repositórios dos grupos

Para evitar que um grupo faça push direto na `deploy` sem revisão:

```
Repositório → Settings → Branches → Add branch protection rule
  Branch name pattern: deploy
  ✅ Require a pull request before merging
  ✅ Require approvals: 1
  ✅ Dismiss stale pull request approvals when new commits are pushed
```

Isso força que toda atualização na branch `deploy` passe por Pull Request com aprovação — ideal para o professor aprovar antes do deploy subir automaticamente.

---

## Operação diária

### Acompanhar logs de um projeto

```bash
# Log do dia atual de um projeto
tail -f logs/projeto-a/$(date +%Y-%m-%d).log

# Log do watcher
tail -f logs/watcher.log
```

### Deploy manual imediato

Quando não quiser esperar o polling de 60s:

```bash
node scripts/deployer.js projeto-a
```

### Ver estado atual de cada projeto

```bash
# Estado salvo (último SHA, timestamp, etc.)
cat state/projeto-a.json

# Containers rodando
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Ver imagens Docker disponíveis por projeto

```bash
docker images | grep projeto-a
# projeto-a-backend   current    abc123...
# projeto-a-backend   previous   def456...
# projeto-a-backend   <sha>      abc123...
```

---

## Rollback manual

O rollback automático acontece em caso de falha no build. Para forçar um rollback manualmente para a versão anterior:

```bash
# Restaurar imagens previous → current
docker tag projeto-a-backend:previous projeto-a-backend:current
docker tag projeto-a-frontend:previous projeto-a-frontend:current

# Subir serviços com a versão restaurada
docker compose -f docker-compose.yml -f compose/projeto-a.yml up -d \
  projeto-a-backend projeto-a-frontend projeto-a-db
```

Para voltar para um SHA específico (ver `docker images`):

```bash
docker tag projeto-a-backend:abc1234 projeto-a-backend:current
docker tag projeto-a-frontend:abc1234 projeto-a-frontend:current

docker compose -f docker-compose.yml -f compose/projeto-a.yml up -d \
  projeto-a-backend projeto-a-frontend projeto-a-db
```

---

## Alterar a porta do backend de um projeto

Se um grupo precisar mudar a porta padrão (3000):

**1. Atualizar `config/projeto-x.json`:**

```json
{
  "backend": {
    "context": ".",
    "dockerfile": "backend/Dockerfile",
    "port": 4000
  }
}
```

**2. Atualizar `nginx/conf.d/routes.conf`** — linha do `proxy_pass` do bloco `/projeto-x/api/`:

```nginx
proxy_pass http://projeto-x-backend:4000/;
```

**3. Reiniciar o Nginx:**

```bash
docker compose restart nginx
```

---

## Atualizar o es-builder

Para puxar atualizações do orquestrador em si:

```bash
cd ~/es-builder
git pull --ff-only

# Reiniciar o Nginx caso o routes.conf tenha mudado
docker compose restart nginx

# Reiniciar o watcher
kill $(cat watcher.pid)
nohup node scripts/watcher.js >> logs/watcher.log 2>&1 &
echo $! > watcher.pid
```

---

## Resolução de problemas

### Nginx não sobe

```bash
# Ver logs do Nginx
docker logs $(docker ps -qf name=nginx)

# Testar configuração manualmente
docker run --rm -v $(pwd)/nginx/conf.d:/etc/nginx/conf.d:ro nginx:alpine nginx -t
```

### Um projeto não recebe deploy

```bash
# Ver o estado atual do projeto
cat state/projeto-a.json

# Se lastFailedSha travar o deploy do mesmo commit, limpar manualmente
# (edite o arquivo e remova o campo lastFailedSha ou zere-o para null)
nano state/projeto-a.json
```

### Container do banco não sobe (healthcheck falhando)

```bash
# Ver logs do container do banco
docker logs projeto-a-db

# Causa mais comum: POSTGRES_USER/PASSWORD/DB não preenchidos no .env
cat envs/projeto-a.env
```

### Rede orq-net não existe

```bash
# A rede é criada pelo docker-compose.yml raiz ao subir o Nginx
docker compose up -d nginx

# Verificar
docker network ls | grep orq-net
```

### Watcher parou de rodar

```bash
# Verificar
ps aux | grep watcher.js

# Reiniciar
nohup node scripts/watcher.js >> logs/watcher.log 2>&1 &
echo $! > watcher.pid
```

### Permissão negada ao rodar docker sem sudo

```bash
# Verificar se o usuário está no grupo docker
groups $USER

# Se não estiver, adicionar e reconectar
sudo usermod -aG docker $USER
exit  # reconectar via SSH
```
