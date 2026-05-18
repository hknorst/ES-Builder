#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup.sh — configuração inicial do es-builder
#
# Execute uma vez no servidor antes de iniciar o watcher.
# =============================================================================

# URLs dos repositórios Git (branch deploy)
# Ajuste para os URLs reais de cada grupo antes de executar
REPO_PORTAL="git@github.com:seu-grupo/portal.git"
REPO_PROJETO_A="git@github.com:seu-grupo/projeto-a.git"
REPO_PROJETO_B="git@github.com:seu-grupo/projeto-b.git"
REPO_PROJETO_C="git@github.com:seu-grupo/projeto-c.git"
REPO_PROJETO_D="git@github.com:seu-grupo/projeto-d.git"
REPO_PROJETO_E="git@github.com:seu-grupo/projeto-e.git"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# =============================================================================
# Criar diretórios necessários (não versionados)
# =============================================================================

echo "Criando diretórios..."
mkdir -p "$ROOT_DIR/state"
mkdir -p "$ROOT_DIR/logs"
mkdir -p "$ROOT_DIR/envs"
mkdir -p "$ROOT_DIR/projects"

# =============================================================================
# Clonar repositórios na branch deploy
# =============================================================================

clone_or_update() {
  local nome="$1"
  local url="$2"
  local destino="$ROOT_DIR/projects/$nome"

  if [ -d "$destino/.git" ]; then
    echo "[$nome] Repositório já existe. Pulando clone."
  else
    echo "[$nome] Clonando branch deploy..."
    git clone --branch deploy --single-branch "$url" "$destino"
  fi
}

clone_or_update "portal"    "$REPO_PORTAL"
clone_or_update "projeto-a" "$REPO_PROJETO_A"
clone_or_update "projeto-b" "$REPO_PROJETO_B"
clone_or_update "projeto-c" "$REPO_PROJETO_C"
clone_or_update "projeto-d" "$REPO_PROJETO_D"
clone_or_update "projeto-e" "$REPO_PROJETO_E"

# =============================================================================
# Criar arquivos .env por projeto (se não existirem)
# =============================================================================

create_env() {
  local nome="$1"
  local env_file="$ROOT_DIR/envs/${nome}.env"

  if [ -f "$env_file" ]; then
    echo "[$nome] .env já existe. Pulando criação."
    return
  fi

  echo "[$nome] Criando envs/${nome}.env..."
  cat > "$env_file" <<EOF
# Variáveis de ambiente para ${nome}
# Preencha antes de iniciar o watcher

# VITE_BASE_PATH é usado no build do frontend (Vite) via --build-arg
# O deployer.js passa este valor dinamicamente; manter aqui apenas para referência
VITE_BASE_PATH=/${nome}/

# BASE_PATH é usado em runtime pelo backend para prefixar rotas
BASE_PATH=/${nome}

# Chave secreta JWT — deve ser IDÊNTICA em todos os projetos
# O portal emite o token; os outros projetos validam com esta mesma chave
JWT_SECRET=

# URL de conexão com o banco de dados PostgreSQL deste projeto
# Formato: postgresql://usuario:senha@${nome}-db:5432/nome_do_banco
DATABASE_URL=

# Credenciais do PostgreSQL (usadas pelo container postgres:16-alpine)
POSTGRES_USER=
POSTGRES_PASSWORD=
POSTGRES_DB=
EOF
}

create_env "portal"
create_env "projeto-a"
create_env "projeto-b"
create_env "projeto-c"
create_env "projeto-d"
create_env "projeto-e"

# =============================================================================
# Subir Nginx (cria a rede orq-net automaticamente)
# =============================================================================

echo ""
echo "Subindo Nginx para criar a rede orq-net..."
cd "$ROOT_DIR"
docker compose up -d nginx
echo "Nginx no ar. Rede orq-net criada."

# =============================================================================
# Instruções finais
# =============================================================================

echo ""
echo "============================================================"
echo " SETUP CONCLUÍDO — PRÓXIMOS PASSOS"
echo "============================================================"
echo ""
echo "1. PREENCHER OS ARQUIVOS .env:"
echo "   Edite os arquivos em envs/*.env e defina:"
echo "   - JWT_SECRET (igual em todos os projetos)"
echo "   - DATABASE_URL"
echo "   - POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB"
echo ""
echo "2. CONFIGURAR DEPLOY KEYS (acesso somente leitura):"
echo "   Gerar par de chaves SSH ed25519:"
echo "   ssh-keygen -t ed25519 -C 'es-builder-deploy' -f ~/.ssh/es-builder_ed25519 -N ''"
echo ""
echo "   Adicionar ao ~/.ssh/config:"
echo "   Host github.com"
echo "     IdentityFile ~/.ssh/es-builder_ed25519"
echo "     IdentitiesOnly yes"
echo ""
echo "   Copiar a chave pública (~/.ssh/es-builder_ed25519.pub)"
echo "   e cadastrar como Deploy Key (read-only) em cada repositório:"
echo "   GitHub → Settings → Deploy Keys → Add deploy key"
echo ""
echo "3. PROTEGER A BRANCH deploy EM CADA REPOSITÓRIO:"
echo "   GitHub → Settings → Branches → Add branch protection rule"
echo "   - Branch name pattern: deploy"
echo "   - Require pull request reviews before merging"
echo "   - Recomendado: exigir aprovação do professor/monitor"
echo ""
echo "4. INICIAR O WATCHER:"
echo "   node scripts/watcher.js"
echo ""
echo "   Para rodar em background com log persistido:"
echo "   nohup node scripts/watcher.js >> logs/watcher.log 2>&1 &"
echo ""
echo "5. DEPLOY MANUAL DE UM PROJETO:"
echo "   node scripts/deployer.js <projeto>"
echo "   Exemplo: node scripts/deployer.js projeto-a"
echo ""
echo "============================================================"
