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

if [ ! -f "$REPOS_FILE" ]; then
  echo "  [aviso] config/repos.json não encontrado — etapa de clone será ignorada."
  echo "          Para clonar os repos: cp config/repos.json.example config/repos.json"
  echo "          Depois edite com as URLs reais dos grupos e execute setup.sh novamente."
  REPOS_CONFIGURADO=false
else
  ok "config/repos.json encontrado"
  REPOS_CONFIGURADO=true
fi

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

  if [[ "$url" == *"sua-org"* ]]; then
    echo "  [$nome] [aviso] URL ainda é placeholder — pulando."
    return
  fi

  if [ -d "$destino/.git" ]; then
    echo "  [$nome] Repositório já existe — pulando."
  else
    echo "  [$nome] Clonando $url ..."
    if git clone --branch deploy --single-branch "$url" "$destino" 2>/dev/null; then
      echo "  [$nome] Clonado (branch deploy)."
    else
      echo "  [$nome] Branch deploy não encontrada. Clonando branch padrão..."
      git clone "$url" "$destino"
      echo "  [$nome] Clonado (branch padrão). Deploy aguardará criação da branch deploy."
    fi
  fi
}

if [ "$REPOS_CONFIGURADO" = true ]; then
  clone_or_update "portal"
  clone_or_update "projeto-a"
  clone_or_update "projeto-b"
  clone_or_update "projeto-c"
  clone_or_update "projeto-d"
  clone_or_update "projeto-e"
else
  echo "  [aviso] Etapa de clone ignorada — repos.json não encontrado."
fi

# =============================================================================
# Criar arquivos .env por projeto (se não existirem)
# =============================================================================

echo ""
echo "=== Criando arquivos .env ==="

# JWT_SECRET gerado uma vez e compartilhado entre todos os projetos.
# Reutiliza apenas se já existir um valor com comprimento mínimo seguro (>=32 chars).
# Valor curto ou vazio é tratado como dummy e substituído.
EXISTING_SECRET=$(grep -h "^JWT_SECRET=" "$ROOT_DIR/envs/"*.env 2>/dev/null | head -1 | cut -d= -f2 || true)
if [ ${#EXISTING_SECRET} -ge 32 ]; then
  JWT_SECRET="$EXISTING_SECRET"
  ok "JWT_SECRET existente reutilizado (${JWT_SECRET:0:8}...)"
else
  JWT_SECRET=$(openssl rand -hex 32)
  ok "JWT_SECRET gerado (${JWT_SECRET:0:8}...)"
fi

create_env() {
  local nome="$1"
  local env_file="$ROOT_DIR/envs/${nome}.env"

  # Considera configurado se DATABASE_URL já estiver preenchida.
  # Protege credenciais existentes (banco pode já ter sido inicializado com elas).
  # Arquivo vazio ou incompleto é tratado como não configurado e reescrito.
  if grep -q "^DATABASE_URL=postgresql://" "$env_file" 2>/dev/null; then
    echo "  [$nome] envs/${nome}.env já configurado — pulando."
    return
  fi

  # Identificadores PostgreSQL não aceitam hífen — converte para underscore
  local db_user="${nome//-/_}_user"
  local db_name="${nome//-/_}_db"
  local db_password
  db_password=$(openssl rand -hex 16)

  echo "  [$nome] Criando envs/${nome}.env..."
  cat > "$env_file" <<EOF
# Variáveis de ambiente para ${nome}
# Gerado automaticamente pelo setup.sh — não editar manualmente

# VITE_BASE_PATH é usado no build do frontend (Vite) via --build-arg
VITE_BASE_PATH=/${nome}/

# BASE_PATH é usado em runtime pelo backend para prefixar rotas
BASE_PATH=/${nome}

# Chave secreta JWT — gerada no setup, idêntica em todos os projetos
JWT_SECRET=${JWT_SECRET}

# Credenciais do PostgreSQL — geradas no setup, específicas deste projeto
POSTGRES_USER=${db_user}
POSTGRES_PASSWORD=${db_password}
POSTGRES_DB=${db_name}

# URL de conexão montada a partir das credenciais acima
DATABASE_URL=postgresql://${db_user}:${db_password}@${nome}-db:5432/${db_name}
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
echo "1. VERIFICAR OS ARQUIVOS .env (gerados automaticamente):"
echo "   JWT_SECRET, DATABASE_URL e credenciais do banco já estão preenchidos."
echo "   Confira se está tudo certo:"
echo "   cat $ROOT_DIR/envs/portal.env"
echo "   cat $ROOT_DIR/envs/projeto-a.env"
echo ""
echo "   Para adicionar variáveis extras de um grupo (ex: SMTP, API keys):"
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
