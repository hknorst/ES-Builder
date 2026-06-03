SHELL := /bin/bash
USER  := $(shell whoami)
DIR   := $(shell pwd)

# ── Tunnel Cloudflare ─────────────────────────────────────────────────────────

.PHONY: tunnel-install tunnel-start tunnel-stop tunnel-status tunnel-url tunnel-uninstall

tunnel-install: ## Instala e habilita o tunnel como serviço systemd (sobrevive a reboot)
	@if [ ! -f /usr/local/bin/cloudflared ]; then \
		echo "Baixando cloudflared..."; \
		sudo curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
			-o /usr/local/bin/cloudflared && sudo chmod +x /usr/local/bin/cloudflared; \
	fi
	@sudo sed -e "s|__USER__|$(USER)|g" -e "s|__WORKDIR__|$(DIR)|g" \
		systemd/es-builder-tunnel.service \
		| sudo tee /etc/systemd/system/es-builder-tunnel.service > /dev/null
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now es-builder-tunnel
	@echo ""
	@echo "Tunnel instalado. Aguarde ~10s e rode: make tunnel-url"

tunnel-url: ## Exibe a URL pública gerada pelo tunnel
	@grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' $(DIR)/logs/tunnel.log 2>/dev/null | tail -1 \
		|| echo "URL ainda não disponível — aguarde alguns segundos e tente novamente."

tunnel-start: ## Inicia o tunnel (sem instalar como serviço)
	@sudo systemctl start es-builder-tunnel
	@echo "Tunnel iniciado. Rode: make tunnel-url"

tunnel-stop: ## Para o tunnel
	@sudo systemctl stop es-builder-tunnel

tunnel-status: ## Mostra o status do tunnel
	@sudo systemctl status es-builder-tunnel --no-pager

tunnel-uninstall: ## Remove o serviço do tunnel
	@sudo systemctl disable --now es-builder-tunnel 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/es-builder-tunnel.service
	@sudo systemctl daemon-reload
	@echo "Tunnel removido."

# ── Watcher ───────────────────────────────────────────────────────────────────

.PHONY: watcher-install watcher-start watcher-stop watcher-status watcher-logs

watcher-install: ## Instala o watcher como serviço systemd
	@sudo sed -e "s|__USER__|$(USER)|g" -e "s|__WORKDIR__|$(DIR)|g" \
		systemd/es-builder-watcher.service \
		| sudo tee /etc/systemd/system/es-builder-watcher.service > /dev/null
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now es-builder-watcher
	@echo "Watcher instalado e rodando."

watcher-start: ## Inicia o watcher
	@sudo systemctl start es-builder-watcher

watcher-stop: ## Para o watcher
	@sudo systemctl stop es-builder-watcher

watcher-status: ## Mostra o status do watcher
	@sudo systemctl status es-builder-watcher --no-pager

watcher-logs: ## Acompanha os logs do watcher em tempo real
	@sudo journalctl -u es-builder-watcher -f

# ── Deploy manual ─────────────────────────────────────────────────────────────

.PHONY: deploy

deploy: ## Deploy manual de um projeto. Uso: make deploy PROJECT=portal
ifndef PROJECT
	$(error PROJECT não definido. Uso: make deploy PROJECT=portal)
endif
	@rm -f $(DIR)/state/$(PROJECT).json
	@node $(DIR)/scripts/deployer.js $(PROJECT)

# ── Ajuda ─────────────────────────────────────────────────────────────────────

.PHONY: help

help: ## Lista todos os comandos disponíveis
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
