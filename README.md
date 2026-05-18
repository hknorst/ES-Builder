# ES-Builder — Orquestrador de Deploy

Ambiente de deploy centralizado para 6 projetos acadêmicos com reverse proxy Nginx, deploy automático via polling de Git e rollback por tags Docker.

## Documentação

| Documento | Para quem |
|-----------|-----------|
| [docs/arquitetura.md](docs/arquitetura.md) | Diagramas de módulos, fluxo de deploy e infraestrutura de containers |
| [docs/guia-admin.md](docs/guia-admin.md) | Professor / monitor — instalar, configurar e operar o servidor |
| [docs/guia-dos-grupos.md](docs/guia-dos-grupos.md) | Grupos de alunos — configurar Dockerfile, vite.config, API e fazer deploy |

---

## Visão geral

```
Navegador
   │
   ▼
Nginx :80
   ├── /portal/         → portal-frontend
   ├── /portal/api/     → portal-backend
   ├── /projeto-a/      → projeto-a-frontend
   ├── /projeto-a/api/  → projeto-a-backend
   └── ...
```

Cada projeto tem seus próprios containers de backend, frontend e banco de dados (PostgreSQL), isolados na rede Docker `orq-net`.

## Fluxo de deploy

```
push na branch deploy
  └─ watcher.js (polling 60s)
       └─ git fetch + rev-parse → SHA
            ├─ sem mudança → pular
            ├─ SHA já falhou → pular
            └─ build backend + build frontend (com VITE_BASE_PATH)
                 ├─ sucesso → previous ← current ← SHA → compose up
                 └─ falha   → rollback automático para previous
```

## Estrutura de rotas

| Projeto   | Frontend      | API               |
|-----------|---------------|-------------------|
| portal    | /portal/      | /portal/api/      |
| projeto-a | /projeto-a/   | /projeto-a/api/   |
| projeto-b | /projeto-b/   | /projeto-b/api/   |
| projeto-c | /projeto-c/   | /projeto-c/api/   |
| projeto-d | /projeto-d/   | /projeto-d/api/   |
| projeto-e | /projeto-e/   | /projeto-e/api/   |

A raiz `/` redireciona para `/portal/`.

## Requisitos do servidor

- Ubuntu Server 20.04 LTS ou mais recente
- Docker Engine >= 20.10
- Docker Compose >= 2 (plugin `docker compose`)
- Node.js >= 18

Instalação automática via bootstrap — ver [docs/guia-admin.md](docs/guia-admin.md).
