# Variáveis de Ambiente — Grupos

Este documento descreve as variáveis de ambiente que cada projeto precisa definir.

Existem dois contextos distintos:

| Contexto | Onde fica | Quem gerencia |
|----------|-----------|---------------|
| **Deploy (servidor)** | `es-builder/envs/projeto-x.env` | Professor / monitor |
| **Desenvolvimento local** | `.env` na raiz do repositório do grupo | O próprio grupo |

---

## Template — desenvolvimento local

Coloque este arquivo na raiz do repositório com o nome `.env` e adicione ao `.gitignore`.

```bash
# .env — desenvolvimento local
# Não commite este arquivo. Adicione .env ao .gitignore.

# ── Banco de dados ────────────────────────────────────────────────

# Em local: usar localhost (PostgreSQL rodando na sua máquina ou via docker-compose local)
# Em deploy: o servidor injeta automaticamente com host = projeto-x-db
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/meu_banco

# Credenciais do PostgreSQL (usadas pelo container postgres:16-alpine)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=meu_banco

# ── Autenticação ──────────────────────────────────────────────────

# Chave secreta para assinar e validar tokens JWT
# Em deploy: o professor define a mesma chave em todos os projetos
# Em local: use qualquer valor — desde que seja idêntico em todos os serviços locais
JWT_SECRET=chave-local-qualquer-mas-longa-o-suficiente

# ── Servidor (backend) ────────────────────────────────────────────

# Porta em que o backend escuta
# Em deploy: deve bater com o EXPOSE no Dockerfile e com config/projeto-x.json → backend.port
PORT=3000

# Ambiente de execução
NODE_ENV=development

# Prefixo de rota (em deploy o servidor injeta automaticamente)
# Em local: pode deixar vazio ou usar / para não precisar de prefixo
BASE_PATH=

# ── Frontend (build) ──────────────────────────────────────────────

# Em deploy: o servidor injeta via --build-arg automaticamente (não editar)
# Em local: pode deixar vazio — o Vite usa / como padrão
VITE_BASE_PATH=/
```

---

## O que cada variável faz

### `DATABASE_URL`

String de conexão com o PostgreSQL. O formato é:

```
postgresql://USUARIO:SENHA@HOST:PORTA/BANCO
```

| Ambiente | HOST |
|----------|------|
| Local | `localhost` |
| Deploy | `projeto-x-db` (nome do container na rede Docker) |

> Nunca use `localhost` no código do backend — use sempre a variável de ambiente.

---

### `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`

Usadas pelo container `postgres:16-alpine` para criar o banco na primeira inicialização. Devem ser consistentes com a `DATABASE_URL`.

```bash
POSTGRES_USER=appuser
POSTGRES_PASSWORD=senha-segura
POSTGRES_DB=projeto_a_db

# DATABASE_URL correspondente:
DATABASE_URL=postgresql://appuser:senha-segura@projeto-a-db:5432/projeto_a_db
```

---

### `JWT_SECRET`

Chave usada para assinar (portal) e validar (demais projetos) tokens JWT.

- Deve ser **idêntica** em todos os projetos no servidor de deploy
- Em local, pode ser qualquer string longa
- Nunca hardcode no código — sempre `process.env.JWT_SECRET`

```ts
// backend — validar token
const payload = jwt.verify(token, process.env.JWT_SECRET)
```

---

### `PORT`

Porta em que o backend escuta. Deve bater com:
- `EXPOSE <porta>` no `backend/Dockerfile`
- `config/projeto-x.json` → campo `backend.port`
- `nginx/conf.d/routes.conf` → `proxy_pass http://projeto-x-backend:<porta>/`

O padrão é `3000`. Se mudar, informe o professor para atualizar a config do servidor.

---

### `BASE_PATH`

Prefixo de rota injetado pelo servidor em runtime. No servidor de deploy vale `/projeto-x`.

Em desenvolvimento local, deixar vazio evita ter que prefixar todas as rotas localmente:

```ts
// backend — Express
const base = process.env.BASE_PATH || ''
app.use(`${base}/api`, router)
// local:  GET /api/usuarios
// deploy: GET /projeto-a/api/usuarios  (após strip pelo Nginx, chega como /api/usuarios)
```

> O Nginx já remove o prefixo `/projeto-x/api/` antes de repassar ao backend.
> Na prática, o backend recebe a requisição sem o prefixo — `BASE_PATH` fica disponível
> para casos onde seja necessário gerar URLs absolutas no backend.

---

### `VITE_BASE_PATH`

Usada como **argumento de build** do Docker para definir o subpath dos assets do frontend.

- **No servidor:** o deployer injeta via `--build-arg` automaticamente. O grupo não precisa definir.
- **Em local:** deixe `/` (padrão) para o frontend funcionar em `http://localhost:5173`

O Vite recebe esse valor via `--base` e o expõe como `import.meta.env.BASE_URL`. No código do frontend, use sempre `BASE_URL` — é a variável padrão do Vite e não depende de nenhuma configuração extra:

```ts
// ✅ Preferido — variável padrão do Vite
const basePath = import.meta.env.BASE_URL  // '/projeto-a/' em deploy, '/' em local

// Exemplo de uso para API
const API_BASE = `${import.meta.env.BASE_URL}api`
```

---

## Adicionando variáveis próprias do projeto

Além das variáveis acima, cada grupo pode adicionar as suas próprias. Exemplos comuns:

```bash
# E-mail / SMTP
SMTP_HOST=smtp.exemplo.com
SMTP_PORT=587
SMTP_USER=no-reply@exemplo.com
SMTP_PASS=senha

# Chaves de API externas
MAPS_API_KEY=...
STORAGE_API_KEY=...

# Configurações da aplicação
MAX_UPLOAD_SIZE_MB=10
SESSION_EXPIRY_HOURS=24
```

Variáveis do frontend devem obrigatoriamente ter o prefixo `VITE_`:

```bash
# Visível no bundle do frontend (via import.meta.env.VITE_*)
VITE_MAPS_API_KEY=...
VITE_FEATURE_FLAG_CHAT=true
```

Peça ao professor para adicioná-las ao arquivo `envs/projeto-x.env` no servidor.

---

## .gitignore do repositório do grupo

Certifique-se de que o `.env` não está versionado:

```gitignore
# Variáveis de ambiente locais
.env
.env.local
.env.*.local

# Dependências
node_modules/
```
