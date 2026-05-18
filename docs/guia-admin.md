# Guia do Administrador

Este documento é para o professor ou monitor responsável pelo servidor. Cobre instalação, configuração inicial, operação diária e resolução de problemas.

---

## Visão geral da responsabilidade

| Quem | Faz o quê |
|------|-----------|
| **Admin (você)** | Instalar dependências, configurar servidor, preencher `.env`, gerenciar Deploy Keys, iniciar watcher |
| **Grupos** | Configurar os próprios projetos (Dockerfile, nginx.conf) e fazer push na branch `deploy` |

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
ssh -T git@github.com-es-builder
# Resposta esperada: Hi <usuario>! You've successfully authenticated...
```

> O alias `github.com-es-builder` é configurado pelo bootstrap para não conflitar com chaves SSH pessoais do administrador.

---

## Passo 3 — Configurar as URLs dos repositórios

Copie o template e preencha com as URLs reais de cada grupo:

```bash
cd ~/es-builder
cp config/repos.json.example config/repos.json
nano config/repos.json
```

Substitua `sua-org` pela organização/usuário correto do GitHub. Use o alias `github.com-es-builder` nas URLs:

```json
{
  "portal":    "git@github.com-es-builder:nome-da-org/portal.git",
  "projeto-a": "git@github.com-es-builder:nome-da-org/projeto-a.git",
  "projeto-b": "git@github.com-es-builder:nome-da-org/projeto-b.git",
  "projeto-c": "git@github.com-es-builder:nome-da-org/projeto-c.git",
  "projeto-d": "git@github.com-es-builder:nome-da-org/projeto-d.git",
  "projeto-e": "git@github.com-es-builder:nome-da-org/projeto-e.git"
}
```

> `config/repos.json` está no `.gitignore` — atualizações do es-builder nunca sobrescrevem essa configuração local.

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

## Passo 5 — Verificar as variáveis de ambiente

O `setup.sh` gerou todos os arquivos `envs/*.env` com credenciais únicas por projeto:

| Variável | Geração |
|----------|---------|
| `JWT_SECRET` | Uma chave compartilhada, igual em todos os projetos |
| `POSTGRES_USER` | Derivado do nome do projeto (ex: `projeto_a_user`) |
| `POSTGRES_PASSWORD` | Senha aleatória por projeto |
| `POSTGRES_DB` | Derivado do nome do projeto (ex: `projeto_a_db`) |
| `DATABASE_URL` | Montada automaticamente das credenciais acima |

Não é necessário editar nada. Para revisar ou depurar:

```bash
cat envs/projeto-a.env
```

> Se precisar regenerar as credenciais de um projeto específico (ex: comprometimento de senha), apague o arquivo e rode `bash scripts/setup.sh` novamente — apenas o arquivo ausente será recriado.

---

## Passo 6 — Instalar o watcher como serviço systemd

O watcher monitora todos os repositórios a cada 60 segundos e reinicia automaticamente em caso de falha ou reboot do servidor.

**Instalar a unit:**

```bash
cd ~/es-builder
sudo sed \
  -e "s|__USER__|$USER|g" \
  -e "s|__WORKDIR__|$(pwd)|g" \
  systemd/es-builder-watcher.service \
  | sudo tee /etc/systemd/system/es-builder-watcher.service > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now es-builder-watcher
```

**Verificar status:**

```bash
sudo systemctl status es-builder-watcher
```

**Ver logs em tempo real:**

```bash
journalctl -u es-builder-watcher -f
# ou direto pelo arquivo de log:
tail -f ~/es-builder/logs/watcher.log
```

**Parar / reiniciar:**

```bash
sudo systemctl stop es-builder-watcher
sudo systemctl restart es-builder-watcher
```

> Para testar sem systemd (útil na primeira execução): `node scripts/watcher.js`

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

Se um grupo precisar mudar a porta padrão (3000), **três arquivos precisam ser atualizados em conjunto** — eles devem sempre estar em sincronia:

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

> Se a porta em `config/projeto-x.json` e em `routes.conf` ficarem diferentes, o Nginx vai rotear para a porta errada e a API vai retornar 502. Sempre atualize os dois juntos.

---

## Backup e restore do banco de dados

O rollback automático não restaura o banco — só as imagens de código. Para proteger os dados dos grupos em caso de falha de migration ou acidente:

**Backup de um projeto:**

```bash
# Exporta o banco para um arquivo .sql no servidor
docker exec projeto-a-db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  > ~/backups/projeto-a-$(date +%Y%m%d-%H%M).sql
```

**Criar diretório de backups antes de usar:**

```bash
mkdir -p ~/backups
```

**Restore de um backup:**

```bash
# Para o backend antes de restaurar (evita conexões abertas)
docker compose -f docker-compose.yml -f compose/projeto-a.yml stop projeto-a-backend

# Restaura o banco
docker exec -i projeto-a-db psql -U "$POSTGRES_USER" "$POSTGRES_DB" \
  < ~/backups/projeto-a-20240101-1200.sql

# Sobe o backend novamente
docker compose -f docker-compose.yml -f compose/projeto-a.yml up -d projeto-a-backend
```

> Para um ambiente acadêmico, fazer backup manual antes de cada semana de entregas é suficiente. Se quiser automatizar, adicione o comando de backup ao cron: `crontab -e` → `0 2 * * * docker exec projeto-a-db pg_dump ...`

---

## Atualizar o es-builder

Para puxar atualizações do orquestrador em si:

```bash
cd ~/es-builder
git pull --ff-only

# Reiniciar o Nginx caso o routes.conf tenha mudado
docker compose restart nginx

# Reiniciar o watcher
sudo systemctl restart es-builder-watcher
```

---

## Resolução de problemas

### Nginx não sobe

```bash
# Ver logs do Nginx
docker logs $(docker ps -qf name=nginx)

# Testar configuração manualmente
docker run --rm -v $(pwd)/nginx/conf.d:/etc/nginx/conf.d:ro nginx:1.27-alpine nginx -t
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

Com systemd, o watcher reinicia automaticamente. Para verificar e agir manualmente:

```bash
# Ver status
sudo systemctl status es-builder-watcher

# Ver logs recentes
journalctl -u es-builder-watcher -n 50

# Forçar reinício
sudo systemctl restart es-builder-watcher
```

### Permissão negada ao rodar docker sem sudo

```bash
# Verificar se o usuário está no grupo docker
groups $USER

# Se não estiver, adicionar e reconectar
sudo usermod -aG docker $USER
exit  # reconectar via SSH
```
