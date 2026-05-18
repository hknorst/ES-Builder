#!/usr/bin/env bash
# bootstrap.sh — instala dependências, gera chave SSH de deploy e clona o es-builder
#
# Compatível com Ubuntu 20.04+ (incluindo 26.04) e Debian 11/12.
# Execute como usuário com sudo (não como root):
#   curl -fsSL https://raw.githubusercontent.com/hknorst/es-builder/main/bootstrap.sh | bash
# ou, após clonar manualmente:
#   bash bootstrap.sh

set -euo pipefail

REPO_URL="https://github.com/hknorst/es-builder.git"
CLONE_DIR="${HOME}/es-builder"
SSH_KEY_PATH="${HOME}/.ssh/es-builder_ed25519"
SSH_CONFIG="${HOME}/.ssh/config"

# Versão mínima de Node.js exigida
NODE_MAJOR=18

# =============================================================================
# Utilitários
# =============================================================================

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

info()    { echo -e "${GREEN}[es-builder]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[aviso]${RESET} $*"; }
err()     { echo -e "${RED}[erro]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}=== $* ===${RESET}"; }

has() { command -v "$1" &>/dev/null; }

version_gte() {
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# =============================================================================
# Verificar root / sudo
# =============================================================================

if [[ $EUID -eq 0 ]]; then
  SUDO=""
  warn "Rodando como root. Recomendado executar como usuário comum com sudo."
else
  if ! has sudo; then
    err "sudo não encontrado. Instale sudo ou execute como root."
    exit 1
  fi
  SUDO="sudo"
fi

# =============================================================================
# Dependências base (inclui openssh-client para ssh-keygen)
# =============================================================================

section "Atualizando índice de pacotes e instalando dependências base"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
  ca-certificates \
  curl \
  git \
  openssh-client

info "git: $(git --version)"
info "ssh-keygen: $(ssh-keygen -V 2>&1 | head -1 || echo 'disponível')"

# =============================================================================
# Docker Engine
#
# Usa get.docker.com — mais robusto para Ubuntu recente (26.04) onde o
# repositório apt por codename pode ainda não ter pacotes disponíveis.
# =============================================================================

section "Verificando Docker Engine"

INSTALL_DOCKER=false

if has docker; then
  DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
  if version_gte "$DOCKER_VER" "20.10"; then
    info "Docker já instalado: $DOCKER_VER — pulando."
  else
    warn "Docker $DOCKER_VER encontrado, mas é necessário >= 20.10. Reinstalando..."
    INSTALL_DOCKER=true
  fi
else
  INSTALL_DOCKER=true
fi

if [[ "$INSTALL_DOCKER" == true ]]; then
  info "Instalando Docker Engine via get.docker.com..."

  $SUDO apt-get remove -y -qq \
    docker docker-engine docker.io containerd runc 2>/dev/null || true

  curl -fsSL https://get.docker.com | $SUDO sh

  if ! docker compose version &>/dev/null; then
    $SUDO apt-get install -y -qq docker-compose-plugin
  fi

  info "Docker instalado: $(docker version --format '{{.Server.Version}}')"
fi

if [[ $EUID -ne 0 ]] && ! groups "$USER" | grep -q docker; then
  $SUDO usermod -aG docker "$USER"
  warn "Usuário '$USER' adicionado ao grupo docker."
  warn "Execute 'newgrp docker' ou faça logout/login para aplicar."
fi

# =============================================================================
# Docker Compose v2
# =============================================================================

section "Verificando Docker Compose v2"

if docker compose version &>/dev/null; then
  info "Docker Compose disponível: $(docker compose version --short)"
else
  info "Instalando docker-compose-plugin..."
  $SUDO apt-get install -y -qq docker-compose-plugin
  info "Docker Compose: $(docker compose version --short)"
fi

# =============================================================================
# Node.js
# =============================================================================

section "Verificando Node.js"

INSTALL_NODE=false

if has node; then
  NODE_MAJOR_INSTALLED=$(node --version | sed 's/v//' | cut -d. -f1)
  if [[ "$NODE_MAJOR_INSTALLED" -ge "$NODE_MAJOR" ]]; then
    info "Node.js já instalado: $(node --version) — pulando."
  else
    warn "Node.js $(node --version) encontrado, mas é necessário >= $NODE_MAJOR. Atualizando..."
    INSTALL_NODE=true
  fi
else
  INSTALL_NODE=true
fi

if [[ "$INSTALL_NODE" == true ]]; then
  info "Instalando Node.js $NODE_MAJOR via NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | $SUDO bash -
  $SUDO apt-get install -y -qq nodejs
  info "Node.js instalado: $(node --version)"
fi

# =============================================================================
# Chave SSH de deploy
#
# Gerada uma única vez. A chave PRIVADA fica em ~/.ssh/ e nunca sai do servidor.
# A chave PÚBLICA é segura de compartilhar — concede apenas leitura (clone/fetch).
# =============================================================================

section "Configurando chave SSH de deploy"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

if [[ -f "$SSH_KEY_PATH" ]]; then
  info "Chave SSH já existe em ${SSH_KEY_PATH} — pulando geração."
else
  info "Gerando chave ed25519 em ${SSH_KEY_PATH}..."
  ssh-keygen -t ed25519 -C "es-builder-deploy" -f "$SSH_KEY_PATH" -N ""
  info "Chave gerada."
fi

# Adicionar bloco ao ~/.ssh/config se ainda não estiver lá
# Alias específico (github.com-es-builder) para não sobrescrever
# chaves SSH pessoais que o admin possa ter para o github.com global.
if ! grep -q "es-builder_ed25519" "$SSH_CONFIG" 2>/dev/null; then
  info "Configurando ~/.ssh/config..."
  cat >> "$SSH_CONFIG" <<EOF

# Adicionado pelo bootstrap.sh do es-builder
# Use git@github.com-es-builder:org/repo.git nas URLs dos repositórios
Host github.com-es-builder
  HostName github.com
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes
EOF
  chmod 600 "$SSH_CONFIG"
  info "~/.ssh/config atualizado."
else
  info "~/.ssh/config já contém a entrada — pulando."
fi

# =============================================================================
# Clonar o repositório es-builder
# =============================================================================

section "Clonando es-builder"

if [[ -d "${CLONE_DIR}/.git" ]]; then
  info "Repositório já existe em ${CLONE_DIR}. Atualizando com git pull..."
  git -C "$CLONE_DIR" pull --ff-only
else
  info "Clonando ${REPO_URL} em ${CLONE_DIR}..."
  git clone "$REPO_URL" "$CLONE_DIR"
fi

# Salvar a chave pública dentro do repositório clonado para fácil acesso
PUB_KEY_FILE="${CLONE_DIR}/deploy-key.pub"
cp "${SSH_KEY_PATH}.pub" "$PUB_KEY_FILE"
info "Chave pública copiada para ${PUB_KEY_FILE}"

# =============================================================================
# Resumo final
# =============================================================================

section "Bootstrap concluído"

echo ""
echo -e "${BOLD}Versões instaladas:${RESET}"
echo "  Docker Engine  : $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'N/D — reinicie o serviço Docker')"
echo "  Docker Compose : $(docker compose version --short 2>/dev/null || echo 'N/D')"
echo "  Node.js        : $(node --version)"
echo "  Git            : $(git --version)"
echo ""
echo -e "${BOLD}Repositório clonado em:${RESET} ${CLONE_DIR}"
echo ""

# Exibir chave pública em destaque para facilitar o cadastro no GitHub
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         CHAVE PÚBLICA DE DEPLOY — CADASTRAR NO GITHUB           ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${CYAN}$(cat "${SSH_KEY_PATH}.pub")${RESET}"
echo ""
echo -e "  Arquivo salvo em: ${BOLD}${PUB_KEY_FILE}${RESET}"
echo -e "  Para exibir novamente: ${BOLD}cat ${PUB_KEY_FILE}${RESET}"
echo ""
echo -e "  Cadastre esta chave (read-only) em ${BOLD}cada${RESET} repositório dos grupos:"
echo "  GitHub → Settings → Deploy Keys → Add deploy key → Allow write access: NÃO"
echo ""

echo -e "${BOLD}Próximos passos:${RESET}"
echo ""
echo "  1. Cadastrar a chave pública acima em todos os repositórios dos grupos"
echo "     (GitHub → Settings → Deploy Keys → Add deploy key → Allow write access: NÃO)"
echo ""
echo "  2. Entrar no diretório:"
echo "     cd ${CLONE_DIR}"
echo ""
echo "  3. Preencher as URLs dos repositórios dos grupos:"
echo "     cp config/repos.json.example config/repos.json"
echo "     nano config/repos.json"
echo "     (use o alias git@github.com-es-builder:org/repo.git)"
echo ""
echo "  4. Executar o setup (verifica pré-requisitos, clona repos, cria .env, sobe Nginx):"
echo "     bash scripts/setup.sh"
echo ""
echo "  5. Preencher as variáveis de cada projeto:"
echo "     nano envs/portal.env"
echo "     nano envs/projeto-a.env"
echo "     # ... repetir para todos os projetos"
echo ""
echo "  6. Instalar o watcher como serviço systemd:"
echo "     sudo sed -e \"s|__USER__|\$USER|g\" -e \"s|__WORKDIR__|\$(pwd)|g\" \\"
echo "       systemd/es-builder-watcher.service \\"
echo "       | sudo tee /etc/systemd/system/es-builder-watcher.service > /dev/null"
echo "     sudo systemctl daemon-reload"
echo "     sudo systemctl enable --now es-builder-watcher"
echo ""

if [[ $EUID -ne 0 ]] && ! groups "$USER" | grep -q docker 2>/dev/null; then
  echo -e "${YELLOW}ATENÇÃO:${RESET} Execute 'newgrp docker' antes de usar o Docker sem sudo."
  echo ""
fi
