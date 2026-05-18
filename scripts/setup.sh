#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup.sh — configuração inicial do es-builder
#
# Execute uma vez no servidor, após bootstrap.sh e após preencher
# config/repos.json com as URLs reais dos repositórios dos grupos.
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_FILE="$ROOT_DIR/config/repos.json"

# =============================================================================
# Utilitários
# =============================================================================

ok()   { echo "  [ok] $*"; }
fail() { echo ""; echo "  [ERRO] $*" >&2; exit 1; }

# Lê o valor de uma chave do repos.json via Python3 (sempre disponível no Ubuntu)
get_repo() {
  python3 -c "import json; print(json.load(open('$REPOS_FILE'))['$1'])"
}

# =============================================================================
# Verificações pré-voo
# =============================================================================

echo ""
echo "=== Verificações pré-voo ==="

docker info &>/dev/null \
  || fail "Docker não está rodando. Execute: sudo systemctl start docker"
ok "Docker Engine disponível"

docker compose version &>/dev/null \
  || fail "Docker Compose v2 não encontrado. Execute: sudo apt-get install docker-compose-plugin"
ok "Docker Compose v2 disponível"

[ -f "$REPOS_FILE" ] \
  || fail "config/repos.json não encontrado.
         Copie o template: cp config/repos.json.example config/repos.json
         Depois edite com as URLs reais dos grupos."
ok "config/repos.json encontrado"

grep -q "sua-org" "$REPOS_FILE" \
  && fail "config/repos.json ainda contém URLs de placeholder (sua-org).
         Edite o arquivo e preencha as URLs reais antes de continuar." || true
ok "config/repos.json preenchido"

echo ""

# =============================================================================
# Criar diretórios necessários (não versionados)
# =============================================================================

echo "=== Criando diretórios ==="
mkdir -p "$ROOT_DIR"/{state,logs,envs,projects}
ok "state/, logs/, envs/, projects/ prontos"

# =============================================================================
# Clonar repositórios na branch deploy
# =============================================================================

echo ""
echo "=== Clonando repositórios ==="

clone_or_update() {
  local nome="$1"
  local url
  url=$(get_repo "$nome")
  local destino="$ROOT_DIR/projects/$nome"

  if [ -d "$destino/.git" ]; then
    echo "  [$nome] Repositório já existe — pulando."
  else
    echo "  [$nome] Clonando $url ..."
    git clone --branch deploy --single-branch "$url" "$destino"
    echo "  [$nome] Clonado."
  fi
}

clone_or_update "portal"
clone_or_update "projeto-a"
clone_or_update "projeto-b"
clone_or_update "projeto-c"
clone_or_update "projeto-d"
clone_or_update "projeto-e"

# =============================================================================
# Criar arquivos .env por projeto (se não existirem)
# =============================================================================

echo ""
echo "=== Criando arquivos .env ==="

create_env() {
  local nome="$1"
  local env_file="$ROOT_DIR/envs/${nome}.env"

  if [ -f "$env_file" ]; then
    echo "  [$nome] envs/${nome}.env já existe — pulando."
    return
  fi

  echo "  [$nome] Criando envs/${nome}.env..."
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
echo "=== Subindo Nginx ==="
cd "$ROOT_DIR"
docker compose up -d nginx
ok "Nginx no ar. Rede orq-net criada."

# =============================================================================
# Instruções finais
# =============================================================================

echo ""
echo "============================================================"
echo " SETUP CONCLUÍDO — PRÓXIMOS PASSOS"
echo "============================================================"
echo ""
echo "1. PREENCHER OS ARQUIVOS .env:"
echo "   Edite cada arquivo em envs/*.env e defina:"
echo "   - JWT_SECRET (mesmo valor em TODOS os projetos)"
echo "   - DATABASE_URL, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB"
echo ""
echo "   Exemplo:"
echo "   nano $ROOT_DIR/envs/portal.env"
echo "   nano $ROOT_DIR/envs/projeto-a.env"
echo ""
echo "2. INSTALAR O WATCHER COMO SERVIÇO SYSTEMD:"
echo "   cd $ROOT_DIR"
echo "   sudo sed -e \"s|__USER__|$USER|g\" -e \"s|__WORKDIR__|$(pwd)|g\" \\"
echo "     systemd/es-builder-watcher.service \\"
echo "     | sudo tee /etc/systemd/system/es-builder-watcher.service > /dev/null"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable --now es-builder-watcher"
echo "   sudo systemctl status es-builder-watcher"
echo ""
echo "3. DEPLOY MANUAL DE UM PROJETO (sem esperar o watcher):"
echo "   node $ROOT_DIR/scripts/deployer.js projeto-a"
echo ""
echo "============================================================"
