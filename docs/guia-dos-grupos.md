# Guia de Configuração — Grupos

Este documento explica tudo que seu grupo precisa fazer para que o projeto funcione no ambiente compartilhado. Leia do começo ao fim antes de começar.

---

## Como funciona a infraestrutura (versão simples)

Existe um servidor central rodando um **Nginx** como portal. Todo o tráfego passa por ele.

```
Navegador
   │
   ▼
Nginx (portal)
   ├── /projeto-a/        → frontend do grupo A
   ├── /projeto-a/api/    → backend do grupo A
   ├── /projeto-b/        → frontend do grupo B
   ├── /projeto-b/api/    → backend do grupo B
   └── ...
```

Cada grupo tem seus próprios containers rodando em isolamento:

- **1 container** de frontend (React/Vite servido pelo Nginx)
- **1 container** de backend (Node.js/qualquer stack)
- **1 container** de banco de dados (PostgreSQL)

O deploy é automático: quando alguém faz push na branch `deploy`, o servidor detecta em até 60 segundos e sobe a nova versão.

---

## Banco de dados — use PostgreSQL. Ponto.

O ambiente suporta **apenas PostgreSQL**. Não há suporte para outros bancos.

| Banco | Situação |
|-------|----------|
| **PostgreSQL 16** | ✅ Suportado e já configurado |
| MySQL / MariaDB | ❌ Não disponível |
| SQLite | ❌ Não use em container (dados perdidos no redeploy) |
| MongoDB | ❌ Não disponível |
| Redis | ❌ Não disponível |

**Por que só PostgreSQL?**

Cada grupo tem um container PostgreSQL próprio, isolado dos outros grupos. O orquestrador já sobe esse container automaticamente — vocês não precisam configurar nada além da `DATABASE_URL` no `.env`.

**String de conexão (DATABASE_URL):**

```
postgresql://USUARIO:SENHA@projeto-x-db:5432/NOME_DO_BANCO
```

- `projeto-x-db` é o hostname dentro da rede Docker (não use `localhost`)
- O usuário, senha e nome do banco são os que você definir nas variáveis `POSTGRES_*`

---

## O que seu grupo precisa configurar

### Checklist rápido

- [ ] `frontend/Dockerfile` com `ARG VITE_BASE_PATH` e `--base` no build
- [ ] `frontend/nginx.conf` com `try_files` para React Router
- [ ] `backend/Dockerfile` funcional
- [ ] URL da API usando `import.meta.env.BASE_URL` (automático — não hardcode)
- [ ] Variáveis de ambiente definidas no servidor

---

## 1. vite.config.ts — nenhuma alteração necessária

O servidor passa `--base` diretamente para o CLI do Vite durante o build. A flag `--base` tem precedência sobre qualquer configuração no `vite.config.ts`, então **vocês não precisam tocar nesse arquivo**.

Mantenham o `vite.config.ts` como está no projeto de vocês.

---

## 2. Dockerfile do frontend — configuração obrigatória

O servidor passa `--build-arg VITE_BASE_PATH=/projeto-x/` automaticamente. O Dockerfile precisa declarar o `ARG` e repassá-lo para o Vite via `--base`:

```dockerfile
# frontend/Dockerfile

# ── Estágio de build ──────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

# OBRIGATÓRIO: declarar o ARG — sem isso o --build-arg é ignorado pelo Docker
ARG VITE_BASE_PATH=/

# --base tem precedência sobre vite.config.ts: não é necessário editar esse arquivo
RUN npx vite build --base="${VITE_BASE_PATH}"

# ── Estágio de produção ───────────────────────────────────────────
FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html

# Configuração do Nginx para SPA (Single Page Application)
# Redireciona 404 para index.html — necessário para React Router funcionar
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
```

> **Se o build do seu projeto faz mais do que só `vite build`** (ex: `tsc -b && vite build`), separe as etapas:
> ```dockerfile
> ARG VITE_BASE_PATH=/
> RUN npx tsc --noEmit && npx vite build --base="${VITE_BASE_PATH}"
> ```

**nginx.conf** que deve acompanhar o frontend:

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # Redireciona todas as rotas para o index.html (necessário para React Router)
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

---

## 3. Dockerfile do backend

Não há restrição de linguagem ou framework para o backend. Apenas garanta que:

1. O container expõe a porta correta (a mesma definida em `config/projeto-x.json`)
2. Lê as variáveis de ambiente via `process.env` (Node.js) ou equivalente

```dockerfile
# backend/Dockerfile — exemplo Node.js/TypeScript

FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine

WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY package*.json ./
RUN npm ci --omit=dev

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

> Se a porta do seu backend não for 3000, informe ao professor para atualizar o `config/projeto-x.json` e o `nginx/conf.d/routes.conf`.

---

## 4. URL da API no frontend — automático, sem configuração manual

O frontend **nunca** deve apontar diretamente para o container do backend.

```ts
// ❌ ERRADO — não funciona fora do container Docker
const API_BASE = 'http://projeto-a-backend:3000'

// ❌ ERRADO — não funciona no navegador do usuário
const API_BASE = 'http://localhost:3000'

// ❌ ERRADO — hardcode: quebra se o projeto mudar de nome
const API_BASE = '/projeto-a/api'

// ✅ CORRETO — automático, funciona em local e em deploy
const API_BASE = `${import.meta.env.BASE_URL}api`
```

**Como funciona a automação?**

O servidor injeta `--base=/projeto-x/` no build do frontend. O Vite expõe esse valor automaticamente como `import.meta.env.BASE_URL`. Resultado:

| Ambiente | `BASE_URL` | `API_BASE` |
|----------|-----------|-----------|
| Local (`npm run dev`) | `/` | `/api` |
| Deploy no servidor | `/projeto-a/` | `/projeto-a/api` |

Vocês não precisam tocar nesse valor — ele muda automaticamente por projeto.

**Por que passar pelo Nginx?**

O navegador não tem acesso direto aos containers. O único ponto de entrada é o Nginx na porta 80. Ele recebe a requisição em `/projeto-a/api/qualquer-rota`, remove o prefixo e repassa para o backend.

**Exemplo prático com fetch:**

```ts
// src/services/api.ts
const API_BASE = `${import.meta.env.BASE_URL}api`

export async function getUsuarios() {
  const res = await fetch(`${API_BASE}/usuarios`)
  return res.json()
}
```

**Exemplo com axios:**

```ts
import axios from 'axios'

const api = axios.create({
  baseURL: `${import.meta.env.BASE_URL}api`,
})

export default api
```

---

## 5. Variáveis de ambiente

O servidor gera e injeta todas as variáveis automaticamente durante o setup. Vocês não precisam configurar nada no servidor — apenas usar as variáveis no código.

| Variável | O que é | Quem configura |
|----------|---------|----------------|
| `JWT_SECRET` | Chave JWT compartilhada entre todos os projetos | Gerado no setup |
| `DATABASE_URL` | String de conexão completa com o banco | Gerado no setup |
| `POSTGRES_USER/PASSWORD/DB` | Credenciais exclusivas do seu projeto | Gerado no setup |
| `BASE_PATH` | Prefixo de rota (ex: `/projeto-a`) | Injetado pelo servidor |

> Consulte o [env-grupos.md](env-grupos.md) para o template de `.env` para desenvolvimento local.

**Variáveis disponíveis no backend (via `process.env`):**

```bash
# String de conexão com o banco (host = container, nunca localhost)
DATABASE_URL=postgresql://projeto_a_user:<senha>@projeto-a-db:5432/projeto_a_db

# Chave JWT — gerada no setup, idêntica em todos os projetos
JWT_SECRET=<injetado automaticamente>

# Prefixo de rota do projeto
BASE_PATH=/projeto-a
```

**Variáveis disponíveis no frontend (via `import.meta.env`):**

O servidor injeta `--base=/projeto-x/` no build via `--build-arg VITE_BASE_PATH`. O Vite expõe esse valor automaticamente como `import.meta.env.BASE_URL` — variável padrão do Vite, sempre disponível sem configuração extra.

```ts
import.meta.env.BASE_URL  // '/projeto-a/' em deploy, '/' em local
```

Use `BASE_URL` para construir a URL da API (ver seção 4). Vocês não precisam criar nem definir essa variável.

> Apenas variáveis prefixadas com `VITE_` ficam disponíveis no bundle. `BASE_URL` é a exceção: é uma variável especial do Vite e sempre funciona.

---

## 6. Autenticação JWT

O **portal** é o único sistema que faz login e emite tokens JWT. Os outros projetos apenas **validam** o token recebido.

**Fluxo:**

```
Usuário → faz login no portal → portal emite JWT
Usuário → acessa projeto-a → envia JWT no header Authorization
projeto-a → valida JWT com a mesma JWT_SECRET → libera ou rejeita
```

**Validar JWT no backend (Node.js com jsonwebtoken):**

```ts
import jwt from 'jsonwebtoken'

function autenticar(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '')

  if (!token) {
    return res.status(401).json({ erro: 'Token não fornecido' })
  }

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET)
    req.usuario = payload
    next()
  } catch {
    return res.status(401).json({ erro: 'Token inválido' })
  }
}
```

> A `JWT_SECRET` é gerada automaticamente durante o setup do servidor e é idêntica em todos os projetos. Nunca hardcode ela no código — leia sempre de `process.env.JWT_SECRET`.

---

## 7. Como fazer o deploy

O deploy é disparado automaticamente por push na branch `deploy`.

```bash
# No repositório do seu grupo:

# Certifique-se de estar na branch deploy
git checkout deploy

# Merge das suas alterações (geralmente vindo de main ou outra branch)
git merge main

# Enviar para o GitHub
git push origin deploy
```

O servidor detecta o push em até **60 segundos** e inicia o build automaticamente.

**Para acompanhar o status**, peça ao professor acesso ao log do servidor:

```bash
# No servidor
tail -f logs/projeto-a/$(date +%Y-%m-%d).log
```

---

## 8. Estrutura de diretórios esperada

O servidor lê os Dockerfiles a partir dos caminhos definidos em `config/projeto-x.json`. A estrutura padrão esperada é:

```
seu-repositorio/
├── backend/
│   └── Dockerfile        ← lido pelo servidor
├── frontend/
│   ├── Dockerfile        ← lido pelo servidor
│   ├── nginx.conf        ← necessário para React Router
│   └── src/
└── ...
```

Se a estrutura do seu projeto for diferente, informe ao professor para ajustar o `config/projeto-x.json`:

```json
{
  "backend": {
    "context": ".",
    "dockerfile": "backend/Dockerfile",
    "port": 3000
  },
  "frontend": {
    "context": ".",
    "dockerfile": "frontend/Dockerfile"
  }
}
```

- `context` é o diretório raiz passado ao `docker build` (relativo à raiz do repositório)
- `dockerfile` é o caminho do Dockerfile (relativo à raiz do repositório)
- `port` é a porta que o backend expõe — deve bater com o `EXPOSE` no Dockerfile

---

## 9. Rollback automático

Se o build falhar (erro no Dockerfile, testes quebrando, etc.), o servidor **volta automaticamente** para a versão anterior. Vocês não perdem o que estava funcionando.

Se for o **primeiro deploy** e ele falhar, o servidor para os containers — não há versão anterior para restaurar.

---

## 10. Migrations de banco — regra importante

O rollback automático restaura apenas as **imagens de código** (backend e frontend). O banco de dados **não é rolbackeado**.

Isso significa: se o deploy novo rodar uma migration que altera o schema (ex: renomeia uma coluna, remove um campo), e depois o servidor precisar voltar para a versão anterior do código, o código antigo vai encontrar um schema diferente do esperado e pode quebrar.

**Regra:** escreva sempre migrations **aditivas**. Nunca remova ou renomeie colunas em um deploy que precisa funcionar com rollback.

| Operação | Segura para rollback? |
|----------|----------------------|
| `ALTER TABLE ADD COLUMN` com valor default | ✅ Sim |
| `CREATE TABLE` | ✅ Sim |
| `CREATE INDEX` | ✅ Sim |
| `ALTER TABLE DROP COLUMN` | ❌ Não |
| `ALTER TABLE RENAME COLUMN` | ❌ Não |
| `DROP TABLE` | ❌ Não |

Se precisar remover ou renomear, faça em duas fases: primeiro deploy deixa o campo obsoleto mas presente; segundo deploy (após estabilizar) remove de fato.

---

## Erros comuns e soluções

| Sintoma | Causa provável | Solução |
|---------|---------------|---------|
| Assets (JS/CSS) com erro 404 | `ARG` ausente no Dockerfile ou `--base` não passado | Confirmar `ARG VITE_BASE_PATH=/` e `npx vite build --base="${VITE_BASE_PATH}"` |
| `VITE_BASE_PATH` ignorado no build | `ARG` não declarado no Dockerfile | Adicionar `ARG VITE_BASE_PATH=/` antes do `RUN npx vite build` |
| API retorna erro de rede | Frontend apontando para `localhost` | Usar `` `${import.meta.env.BASE_URL}api` `` como base URL |
| `Cannot connect to database` | Conexão hardcoded no código em vez de `process.env.DATABASE_URL` | Usar sempre `process.env.DATABASE_URL` |
| React Router mostra 404 ao navegar | Nginx do frontend não configurado para SPA | Adicionar `try_files $uri /index.html` no `nginx.conf` |
| Token JWT inválido | `JWT_SECRET` não injetado no servidor | Pedir ao professor para verificar `envs/projeto-x.env` no servidor |

---

## Resumo em uma página

```
1. frontend/Dockerfile
   ARG VITE_BASE_PATH=/
   RUN npx vite build --base="${VITE_BASE_PATH}"
   (vite.config.ts não precisa de alteração)

2. frontend/nginx.conf
   try_files $uri $uri/ /index.html;

3. URL da API no frontend
   baseURL: `${import.meta.env.BASE_URL}api`   ← automático, nunca hardcode

4. Backend
   DATABASE_URL via process.env.DATABASE_URL  ← injetado pelo servidor, não hardcode
   JWT_SECRET via process.env.JWT_SECRET      ← injetado pelo servidor, não hardcode

5. Deploy
   git push origin deploy
```
