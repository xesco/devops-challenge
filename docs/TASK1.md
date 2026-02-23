# Task 1: Containerize the Application

## Goal

Produce a production-ready Docker image for the Next.js application and wire it
into `docker-compose.yaml` so `docker compose up` starts both services.

---

## Files Created / Modified

| File                    | Action | Summary                                                     |
|-------------------------|--------|-------------------------------------------------------------|
| `Dockerfile`            | Create | Multi-stage build (deps -> migrator / builder -> runner)    |
| `next.config.ts`        | Modify | Add `output: "standalone"`                                  |
| `docker-compose.yaml`   | Modify | Fix DB hostname; healthcheck; externalize secrets; restart  |
| `.dockerignore`         | Modify | Exclude generated files, docs, `.env*` variants             |
| `app/healthz/route.ts`  | Create | Lightweight health endpoint returning 200, no DB dependency |
| `app/readyz/route.ts`   | Create | DB-aware readiness endpoint: pings DB via `SELECT 1`, returns 200/503 |
| `package.json`          | Modify | Add `packageManager: "pnpm@10.30.1"` as single source of truth |
| `mise.toml`             | Modify | Pin `pnpm = "10.30.1"` instead of `"latest"`                |

---

## Step 1 - `next.config.ts`: enable standalone output

```ts
const nextConfig: NextConfig = {
  output: "standalone",
};
```

`output: "standalone"` makes Next.js emit a self-contained `server.js` bundle
under `.next/standalone/` with only the `node_modules` subset actually used
(tree-shaken). The final image needs no `pnpm install` - smaller image, faster
startup. Without this flag the only way to run the app is `next start`, which
requires the full `node_modules` tree.

---

## Step 2 - `Dockerfile`: multi-stage build

Four stages keep the final image minimal and separate concerns.

### Stage 1 - `deps` (`node:22-alpine`)

- `package.json` is copied first so `corepack prepare --activate` can read the
  `packageManager` field (`"pnpm@10.30.1"`) — the single source of truth for the
  pnpm version. No version is hardcoded in the Dockerfile itself.
- Copy remaining dependency-resolution files: `pnpm-lock.yaml`,
  `pnpm-workspace.yaml`, and the full `prisma/` directory (schema is required
  for `prisma generate`, which runs via the `postinstall` hook).
- `pnpm install --frozen-lockfile` for a reproducible install. The `postinstall`
  hook runs `prisma generate`, writing the client to `prisma/generated/`.

Separating dependency installation means Docker caches `node_modules`
independently. Source-only changes skip `pnpm install` entirely.

### Stage 2a - `migrator` (`node:22-alpine`)

- Branches off `deps` - carries Prisma CLI, migration SQL, and
  `prisma.config.ts`, but no application code.
- Copies `node_modules/` directly from `deps` — no need to reinstall pnpm or
  corepack since `prisma migrate deploy` is invoked directly via
  `node_modules/.bin/prisma`, bypassing pnpm entirely.
- Entrypoint: `node_modules/.bin/prisma migrate deploy`.
- Used by the Kubernetes migration Job (Task 2). The runner image has no Prisma
  CLI or migration files, so a separate stage is needed.
- Runs as the built-in `node` user (UID 1000) - no custom user creation needed.

A Job runs once per deploy. An init container would run once per pod - multiple
replicas means concurrent migration attempts (wasteful, potential race).

### Stage 2b - `builder` (`node:22-alpine`)

- Copies `node_modules/` and `prisma/generated/` from `deps`, then copies
  application source (including `package.json`).
- Runs `node_modules/.bin/next build` directly — same as `pnpm build` which
  just invokes `next build` anyway, but without needing pnpm or corepack in
  this stage.
- Sets `NEXT_TELEMETRY_DISABLED=1` to suppress anonymous telemetry during build
  (avoids outbound network calls, keeps output clean).

No `POSTGRES_PRISMA_URL` needed at build time - `app/page.tsx` sets
`export const dynamic = "force-dynamic"`, deferring all DB access to request
time.

### Stage 3 - `runner` (`node:22-alpine`)

- Creates non-root system user `nextjs:nodejs` (UID/GID 1001) for
  least-privilege.
- Copies minimal artifacts: `.next/standalone/` (server + trimmed
  `node_modules`), `.next/static/` (standalone omits these for CDN offload -
  copied for self-hosted serving), and `public/`.
- Env: `NODE_ENV=production`, `PORT=3000`, `HOSTNAME=0.0.0.0` (binds all
  interfaces).
- `HEALTHCHECK` using `wget` (ships with Alpine, no extra packages). Uses
  `127.0.0.1` instead of `localhost` because BusyBox wget doesn't resolve
  `localhost` reliably. Hits `/healthz` — a dedicated route that returns `200 ok`
  immediately without touching the database. This reflects process liveness, not
  DB availability, which is the correct signal for a container healthcheck.
  `--start-period=30s` gives the Node process time to initialize before failures count.
- Entrypoint: `CMD ["node", "server.js"]` - runs standalone server directly.

**Why `node:22.22-alpine`?** Smallest images (~150-200 MB vs ~400 MB with
`node:22-slim`). Matches Node 22 LTS in `.nvmrc`/`mise.toml`. No native addons
requiring glibc, so musl (Alpine) is safe.

**Why minor version tag, not digest?** `node:22.22-alpine` prevents surprise
breakage while still picking up Alpine security patches on rebuild. Digest
pinning freezes everything - no patches without manual updates. The project has
`renovate.json`; if wired up for Dockerfile images, digest pinning becomes
viable.

---

## Step 3 - `docker-compose.yaml`: networking and healthcheck

### 3a. Fix the database hostname

Change `host.docker.internal` to `postgres` in `POSTGRES_PRISMA_URL`.

`host.docker.internal` resolves to the host IP - unavailable on Linux Docker
Engine (standard in CI/production) without extra config. On the same
Compose-managed network, the service name `postgres` resolves via Docker DNS.

### 3b. Add postgres healthcheck

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres -d currencies"]
  interval: 5s
  timeout: 5s
  retries: 10
```

With `depends_on: { postgres: { condition: service_healthy } }`. Without a
healthcheck, `depends_on` only waits for container start, not DB readiness.
`pg_isready` confirms connections are accepted before the app starts.

### 3c. Externalize credentials

Replace hardcoded passwords with `${POSTGRES_USER}` / `${POSTGRES_PASSWORD}`
env var references. Values from `.env` (git-ignored) or a secrets manager.
Hardcoded passwords in compose files are committed to source control - bad
practice even for local dev.

### 3d. `restart: unless-stopped` instead of `restart: always`

`always` restarts even after deliberate `docker compose stop` - surprising
during development. `unless-stopped` restarts on failure and daemon restart but
respects explicit stops.

---

## Step 4 - `.dockerignore`: tighten the build context

Added: `prisma/generated` (must be regenerated inside build, not copied from
host - stale files could shadow freshly generated ones), `*.md` (docs not
needed in image), `.env*` (no secrets in build context).

Lean context = faster builds + no risk of baking local files into the image.

---

## Security Considerations

- Non-root user in runner stage (limits blast radius)
- No secrets baked into image (runtime env vars from `.env` or secrets manager)
- Base image pinned to specific minor version (supply-chain auditability)
- `.dockerignore` excludes `.env*`, `node_modules`, `prisma/generated/`, `.next`, `.git`
- `--frozen-lockfile` ensures exact dependency tree (no silent upgrades)
- pnpm version pinned via `packageManager` field in `package.json` — corepack reads it automatically, no hardcoded version in the Dockerfile

## Image Size

Final image contains only: Node 22 Alpine runtime, standalone server bundle
with trimmed `node_modules`, static assets, and `public/`. Build tools (pnpm,
TypeScript, Prisma CLI, dev dependencies) are left in builder stage.
