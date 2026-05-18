# Arquitetura do ES-Builder

Este documento descreve a estrutura do projeto em três visões complementares.

> O orquestrador é escrito em JavaScript funcional — sem classes ou orientação a objetos.
> O equivalente ao diagrama de classes aqui é o **diagrama de módulos**: o que cada script
> exporta, o que importa e quais funções contém.

---

## 1. Módulos e dependências (equivalente ao diagrama de classes)

```mermaid
graph TD
    subgraph scripts/
        U["utils.js
        ─────────────────
        exports:
        • PROJETOS_PERMITIDOS
        • ROOT_DIR
        • run(cmd, opts)
        • loadState(project)
        • saveState(project, state)
        • log(project, message)"]

        D["deployer.js
        ─────────────────
        internals:
        • retagImage(from, to)
        • composeUp(project)
        • composeStop(project)
        • deployProject(project)
        ─────────────────
        exports:
        • deployProject(project)"]

        W["watcher.js
        ─────────────────
        internals:
        • verificarTodosProjetos()
        • iniciarWatcher()
        ─────────────────
        entrypoint: node watcher.js"]
    end

    U -->|"PROJETOS_PERMITIDOS, ROOT_DIR
    run, loadState, saveState, log"| D
    U -->|"PROJETOS_PERMITIDOS, log"| W
    D -->|"deployProject"| W

    subgraph "sistema de arquivos"
        S["state/projeto-x.json
        ─────────────────
        lastSuccessSha
        previousSha
        lastFailedSha
        lastDeployAt"]

        L["logs/projeto-x/
        ─────────────────
        YYYY-MM-DD.log"]

        C["config/projeto-x.json
        ─────────────────
        backend.context
        backend.dockerfile
        backend.port
        frontend.context
        frontend.dockerfile"]
    end

    D -->|"lê"| C
    D -->|"lê/escreve"| S
    U -->|"escreve"| L
```

---

## 2. Fluxo do deploy (máquina de estados)

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle --> FetchGit : watcher acorda (60s)

    FetchGit --> ComparaSHA : git fetch + rev-parse

    ComparaSHA --> Idle : SHA == lastSuccessSha\n(sem mudanças)
    ComparaSHA --> Idle : SHA == lastFailedSha\n(já falhou, pular)
    ComparaSHA --> ResetRepo : SHA novo

    ResetRepo --> BuildBackend : git reset --hard origin/deploy

    BuildBackend --> BuildFrontend : sucesso
    BuildBackend --> SalvaFalha : timeout / erro

    BuildFrontend --> PromoveTags : sucesso
    BuildFrontend --> SalvaFalha : timeout / erro

    PromoveTags --> ComposeUp : current→previous\nsha→current

    ComposeUp --> SalvaEstado : docker compose up -d
    ComposeUp --> SalvaFalha : erro

    SalvaEstado --> Idle : lastSuccessSha = sha ✅

    SalvaFalha --> TemPrevious : lastFailedSha = sha

    TemPrevious --> Rollback : previousSha existe
    TemPrevious --> PararContainers : primeiro deploy

    Rollback --> Idle : previous→current\ncompose up ♻️

    PararContainers --> Idle : compose stop ⛔
```

---

## 3. Arquitetura de containers e rede

```mermaid
graph TD
    Browser["🌐 Navegador"]

    subgraph "Host — Ubuntu Server"
        subgraph "rede Docker: orq-net"
            Nginx["nginx:alpine
            porta 80:80
            routes.conf"]

            subgraph "portal"
                PF["portal-frontend\nportal-frontend:current"]
                PB["portal-backend\nportal-backend:current"]
                PD[("portal-db\npostgres:16-alpine")]
            end

            subgraph "projeto-a"
                AF["projeto-a-frontend\nprojeto-a-frontend:current"]
                AB["projeto-a-backend\nprojeto-a-backend:current"]
                AD[("projeto-a-db\npostgres:16-alpine")]
            end

            subgraph "projeto-b … projeto-e"
                DOTS["(mesma estrutura)"]
            end
        end

        subgraph "es-builder (host)"
            W2["node watcher.js"]
            D2["node deployer.js"]
            GIT["projects/\nclones git"]
            IMG["Docker images\n:current :previous :sha"]
        end
    end

    Browser -->|"HTTP :80"| Nginx
    Nginx -->|"/portal/"| PF
    Nginx -->|"/portal/api/"| PB
    Nginx -->|"/projeto-a/"| AF
    Nginx -->|"/projeto-a/api/"| AB

    PB -->|"TCP 5432"| PD
    AB -->|"TCP 5432"| AD

    W2 -->|"spawna"| D2
    D2 -->|"git fetch/reset"| GIT
    D2 -->|"docker build"| IMG
    D2 -->|"docker compose up"| Nginx
```

---

## 4. Ciclo de vida de uma imagem Docker

```mermaid
graph LR
    subgraph "a cada deploy bem-sucedido"
        A["projeto-a-backend:sha_antigo"]
        B["projeto-a-backend:previous"]
        C["projeto-a-backend:current"]
        D["projeto-a-backend:sha_novo"]

        A -->|"retag (se havia current)"| B
        C -->|"retag"| B
        D -->|"retag"| C
    end

    subgraph "em caso de falha"
        B2["previous"] -->|"retag"| C2["current"]
        C2 -->|"compose up"| R["serviço restaurado ♻️"]
    end
```

---

## 5. Responsabilidade de cada arquivo

| Arquivo | Camada | Responsabilidade |
|---------|--------|-----------------|
| `scripts/utils.js` | Utilitários | Shell, I/O de estado e log |
| `scripts/deployer.js` | Orquestração | Lógica de deploy, build e rollback |
| `scripts/watcher.js` | Agendamento | Loop de polling e disparo de deploys |
| `scripts/setup.sh` | Bootstrap | Clone de repos, criação de envs, subir Nginx |
| `bootstrap.sh` | Instalação | Dependências do SO, SSH key, clone do orquestrador |
| `docker-compose.yml` | Infraestrutura | Rede `orq-net` e container Nginx |
| `compose/projeto-x.yml` | Infraestrutura | Containers backend, frontend e db por projeto |
| `nginx/conf.d/routes.conf` | Roteamento | Strip de prefixo e proxy reverso |
| `config/projeto-x.json` | Configuração | Paths de Dockerfile e porta por projeto |
| `envs/projeto-x.env` | Configuração | Variáveis de ambiente por projeto (não versionado) |
| `state/projeto-x.json` | Estado | SHAs de deploy por projeto (não versionado) |
