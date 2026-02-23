# Architecture Overview

A guide for engineers new to this tech stack. Explains what the app does, what
each technology is, how the pieces connect, and what happens at runtime.

---

## What the App Does

A single-page web app displaying a live table of cryptocurrency prices (Bitcoin,
Ethereum, Dogecoin). Prices are stored in PostgreSQL. When a user opens the
page, the server queries the database and renders the table as HTML before
sending it to the browser - no client-side API calls.

---

## Architecture at a Glance

```
Browser
  |
  |  HTTP request (GET /)
  v
Next.js server  (Node.js process)
  |
  |  SQL query via Prisma ORM
  v
PostgreSQL database
  |
  |  rows: name, code, icon, price
  v
Next.js renders HTML + streams it back to the browser
```

Both services are defined in `docker-compose.yaml`. PostgreSQL uses a pre-built
image from Docker Hub. The `nextjs` service is built from the project root
`Dockerfile` - a four-stage build (`deps -> builder / migrator -> runner`) that
produces a minimal Alpine-based production image.

For local development without Docker, Next.js runs via `pnpm dev` and connects
to the PostgreSQL container at `localhost:5432`.

---

## Technologies

### TypeScript

JavaScript with a type system. You write `.ts`/`.tsx` files; the compiler checks
for type errors, then strips annotations to produce plain JavaScript. Catches
bugs at edit time (e.g. calling `.toUpperCase()` on a `Decimal` field errors
immediately). `strict: true` enables all strict checks (can't use possibly
`null`/`undefined` values without checking). `.tsx` files contain JSX (HTML-like
UI syntax).

### Node.js

Runtime that lets JavaScript run outside a browser - on a server. Same role as
JVM for Java or CPython for Python. Next.js needs it to handle HTTP requests,
run DB queries, and render HTML. Requires **Node 22 LTS**.

### Next.js (App Router)

Web framework built on React. Handles routing, server-side rendering, bundling.

- **App Router** - each folder inside `app/` maps to a URL (`app/page.tsx` ->
  `/`, `app/about/page.tsx` -> `/about`).
- **Server Components** (default) run only on the server, can query databases,
  never ship code to the browser. `app/page.tsx` and `components/table.tsx` are
  Server Components.
- **Client Components** (`"use client"`) run in the browser for interactivity
  (state, event handlers). Only used when needed.
- **Streaming with Suspense** - `<Suspense fallback={<TablePlaceholder />}>`
  sends the page shell immediately, streams `<Table>` once the DB query
  finishes. User sees a skeleton instead of a blank page.
- **`export const dynamic = "force-dynamic"`** - prevents page caching. Without
  it, Next.js might render once at build time and serve stale prices forever.
- **Turbopack** - fast dev bundler (replaces Webpack for `pnpm dev`). Only
  recompiles what changed. Production builds use the standard compiler.

### React

UI library. Describe your interface as a tree of components (functions returning
JSX) and React handles rendering. Next.js builds on top of it. The main React
concept visible here is `<Suspense>` for streaming.

### PostgreSQL

Relational database with typed columns, queried with SQL.

- Single `currencies` table: `id`, `name`, `code`, `icon` (base64 SVG),
  `price`, `createdAt`.
- Initial migration seeds three rows (Bitcoin, Ethereum, Dogecoin).
- **Local dev:** runs as `postgres` service in Docker Compose on port 5432.
  Named volume persists data across restarts.
- **Production:** Cloud SQL for PostgreSQL (`db-f1-micro`, ZONAL). The app
  never connects directly — a **Cloud SQL Auth Proxy** sidecar in each pod
  opens a secure tunnel and listens on `127.0.0.1:5432`. Credentials and the
  instance connection name are injected from Kubernetes Secrets provisioned by
  Terraform.

### Prisma

ORM (Object-Relational Mapper) - write TypeScript instead of raw SQL.

- **Schema** (`prisma/schema.prisma`) - source of truth for DB structure.
  Declares the `currencies` model; generates migrations and a typed client.
- **Generated client** (`prisma/generated/`) - auto-generated TypeScript with
  typed query methods like `prisma.currencies.findMany()`.
- **`@prisma/adapter-pg`** - driver adapter using `node-postgres` (`pg`) for
  connection pooling. Recommended pattern for Prisma 7.
- **`prisma.config.ts`** - configures CLI (schema path, migration path, DB
  URL). Only used by CLI commands; runtime client uses `POSTGRES_PRISMA_URL`.
- **Singleton** (`lib/prisma.ts`) - stored on `globalThis` in dev to prevent
  new connection pools on every hot reload.

### Tailwind CSS

Utility-first CSS framework - style by composing classes in JSX:

```tsx
<div className="p-12 rounded-lg shadow-xl">
```

Version 4 uses CSS-first config: no `tailwind.config.js`. `app/globals.css`
imports Tailwind and defines custom values in `@theme {}`. Brand colors
(`--color-moonpay: #7715F5`, `--color-cosmos: #39107A`) become utilities:
`text-moonpay`, `hover:text-cosmos`.

### pnpm

Node.js package manager (alternative to npm/yarn). Faster, uses less disk via
hard-linking from a shared content-addressable store. `pnpm-lock.yaml` pins
every dependency to an exact version. The `postinstall` hook runs
`prisma generate` after every install.

### mise

Version manager for language runtimes and tools. Reads `mise.toml` and
activates the right versions when entering the project directory (like `nvm` but
for many tools). Declares `node = "lts"` (Node 22) and `pnpm = "10.30.1"`.

### Docker & Docker Compose

Docker packages an application into an isolated, reproducible container.
Compose orchestrates multiple containers via `docker-compose.yaml`.

- **`postgres` service** - official `postgres:17-alpine` image from Docker Hub.
  Used for local development only.
- **`nextjs` service** - `build: .`, built from the project `Dockerfile`. Both
  run on Docker's internal network; Next.js reaches Postgres at `postgres:5432`.
- **Production** uses Cloud SQL instead of the `postgres` Docker service. The
  Auth Proxy sidecar in each pod replaces the in-cluster StatefulSet.

### Turbo

Monorepo build system / task runner. Runs tasks in parallel with caching.
Mostly scaffolding here - `turbo.json` defines pipelines (`build`, `dev`,
`lint`) but the repo has one package. Main effect: `turbo build` calls
`next build` with caching.

---

## File & Folder Map

```
devops-challenge/
|
├── app/                        # App Router - one folder = one route
│   ├── page.tsx                # Route "/" - queries DB, renders page
│   ├── layout.tsx              # Wraps every page: <html>, font
│   ├── globals.css             # Tailwind import + brand colors + base styles
│   ├── healthz/
│   │   └── route.ts            # Route "/healthz" - 200 OK, no DB (liveness + startup probes)
│   ├── readyz/
│   │   └── route.ts            # Route "/readyz" - SELECT 1 DB ping, 200/503 (readiness probe)
│   └── fonts/                  # Local font files (Luna variable font)
|
├── components/
│   ├── table.tsx               # Server Component - receives data, renders rows
│   └── table-placeholder.tsx   # Loading skeleton (Suspense fallback)
|
├── lib/
│   └── prisma.ts               # Prisma client singleton (one DB pool)
|
├── prisma/
│   ├── schema.prisma           # Database schema (source of truth)
│   ├── migrations/             # SQL migration files
│   └── generated/              # Auto-generated TypeScript client (gitignored)
|
├── k8s/
│   ├── app/                    # K8s manifests for the app (deployment, service, hpa)
│   └── migration/              # K8s manifests for the Prisma migration Job
|
├── terraform/                  # GKE, Cloud SQL, Artifact Registry, IAM, GitHub env + secrets
|
├── .github/
│   └── workflows/
│       └── release.yml         # Semantic versioning + build + migrate + deploy (fully automated)
|
├── scripts/                    # Lifecycle scripts (create, destroy, migrate, cd-test-*)
├── Makefile                    # Infra lifecycle + CD testing (make create, make destroy, make cd-test-*)
├── .releaserc.json             # semantic-release plugin configuration
├── CONTRIBUTING.md             # Conventional commits guide
├── prisma.config.ts            # Prisma CLI configuration
├── public/                     # Static files served as-is (SVG logos)
├── docker-compose.yaml         # postgres + nextjs services
├── Dockerfile                  # Four-stage build (deps -> builder / migrator -> runner)
├── .env.example                # Template for required env vars
├── package.json                # Dependencies and scripts
├── tsconfig.json               # TypeScript configuration
├── next.config.ts              # Next.js configuration
└── mise.toml                   # Tool versions (Node, pnpm)
```

---

## Request Lifecycle

What happens when a user opens `http://localhost:3000`:

1. **Browser** sends `GET /` to Next.js.
2. **`app/page.tsx`** - Next.js matches the route, calls the `Home` async Server
   Component. It calls `prisma.currencies.findMany()`.
3. **Prisma** translates to `SELECT * FROM currencies`, sends to PostgreSQL via
   the `pg` connection pool.
4. **PostgreSQL** returns three rows.
5. **`Home`** passes rows to `<Table>`, wrapped in
   `<Suspense fallback={<TablePlaceholder />}>`.
6. **Streaming** - Next.js immediately sends the page shell (header, layout,
   skeleton). Browser renders it before the query completes.
7. `<Table>` renders real rows. Next.js streams the HTML diff; browser swaps
   the skeleton out.
8. **Browser** displays the final page - pure server-rendered HTML, no
   JavaScript needed for table content.
