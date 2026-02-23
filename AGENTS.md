# AGENTS.md — DevOps Challenge (MoonPay)

Guidance for AI coding agents working in this repository.

---

## Project Overview

A **Next.js 16 App Router** application that displays live cryptocurrency prices
from a **PostgreSQL 17** database via **Prisma 7** ORM. The primary open task is
writing the `Dockerfile` for the `nextjs` service referenced in
`docker-compose.yaml` (`build: .`).

**Stack:**

| Concern       | Technology                                      |
|---------------|-------------------------------------------------|
| Language      | TypeScript 5.9 (strict mode, ESM)               |
| Runtime       | Node.js 22 LTS                                  |
| Framework     | Next.js 16 (App Router, Turbopack)              |
| Database      | PostgreSQL 17                                   |
| ORM           | Prisma 7 with `@prisma/adapter-pg` driver       |
| Styling       | Tailwind CSS 4 (CSS-first, no config file)      |
| Package mgr   | pnpm (workspace layout)                         |
| Monorepo tool | Turbo 2.x                                       |
| Linting       | ESLint 9 (`next/core-web-vitals`)               |
| Formatting    | Prettier (defaults — no `.prettierrc`)          |

---

## Environment Setup

1. **Node version** — use Node 22 (see `.nvmrc` / `mise.toml`).
2. **Install dependencies** — `pnpm install` also runs `prisma generate`
   automatically via the `postinstall` hook.
3. **Required env var** — `POSTGRES_PRISMA_URL` (connection string to Postgres).
   Copy `.env.example` to `.env` and fill it in.
4. **Database** — start Postgres with `docker compose up postgres -d`, then run
   migrations: `pnpm db:migrate`.

---

## Commands

### Development

```bash
pnpm dev          # Start dev server with Turbopack (hot reload)
pnpm build        # Production build (Next.js)
pnpm start        # Start production server (requires prior build)
```

### Database

```bash
pnpm db:migrate   # Apply Prisma migrations (prisma migrate dev)
pnpm db:push      # Push schema without migration history (prisma db push)
pnpm db:studio    # Open Prisma Studio GUI
```

### Docker

```bash
docker compose up               # Start both postgres + nextjs services
docker compose up postgres -d   # Start only the database
docker compose build            # Build the nextjs image (requires Dockerfile)
```

### Linting / Type-checking

There is no dedicated lint script; ESLint runs as part of `next build`.
To run ESLint manually:

```bash
pnpm exec next lint
```

To type-check without building:

```bash
pnpm exec tsc --noEmit
```

### Tests

**There are no tests in this project.** No test runner, framework, or test files
exist. Do not add a test command that will silently succeed on an empty suite.
If tests are introduced, register the command in `package.json` and note it here.

---

## Code Style

### Formatting

- **Prettier** with all defaults (no config file):
  - 80-character print width (soft), 120-character hard ruler.
  - 2-space indentation.
  - Double quotes for strings (JS/TSX default).
  - Semicolons: yes.
  - Trailing commas: `"all"` (Prettier 3 default).
- Format on save is configured in `.vscode/settings.json`.
- Imports are auto-organized on save (`source.organizeImports: always`).
- All files must end with a newline (`files.insertFinalNewline: true`).

### TypeScript

- **`"strict": true`** — all strict flags are enabled; never disable them.
- **No explicit return types** on React components (inferred). Add them for
  library/util functions where it improves clarity.
- Use `type` aliases for prop shapes (not `interface`):

  ```ts
  type Props = {
    currencies: Prisma.currenciesGetPayload<{ select: { name: boolean } }>[];
  };
  ```

- Use Prisma-generated types (`Prisma.*GetPayload<...>`) for database result
  shapes instead of hand-rolling equivalent types.
- Use `declare global { var foo: T | undefined }` for Next.js dev-mode
  singletons (see `lib/prisma.ts`).

### Imports

- **Path alias `@/`** resolves to the project root (configured in
  `tsconfig.json`). Prefer `@/` for cross-directory imports:

  ```ts
  import { PrismaClient } from "@/prisma/generated/client";
  ```

- VS Code is configured to prefer relative imports for TypeScript
  (`typescript.preferences.importModuleSpecifier: "relative"`), so the
  auto-import tool may generate relative paths. Either style is acceptable;
  be consistent within a file.
- **Import order** (enforced by `source.organizeImports`):
  1. Node built-ins
  2. External packages (`next`, `react`, `pg`, …)
  3. Internal aliases (`@/…`) or relative paths

### Naming Conventions

| Scope              | Convention         | Example                        |
|--------------------|--------------------|--------------------------------|
| Files              | kebab-case         | `table-placeholder.tsx`        |
| React components   | PascalCase         | `TablePlaceholder`             |
| Functions/vars     | camelCase          | `connectionString`, `pool`     |
| Constants          | camelCase          | `dynamic` (Next.js segment)    |
| Prisma models      | lowercase plural   | `currencies` (mirrors DB table)|
| CSS custom props   | kebab-case         | `--color-moonpay`              |

- React components are exported as `export default function ComponentName`.
- Server components that perform I/O are `async`.

### React / Next.js Patterns

- Use **Server Components** by default (App Router). Only add `"use client"` when
  browser APIs or React state/effects are required.
- Streaming: wrap async server components with `<Suspense fallback={...}>` in
  the parent page.
- Route segment config (`export const dynamic = "force-dynamic"`) is placed at
  the top of the file, just below imports.
- Use `next/image` (`<Image>`) for all `<img>` tags; always provide `width`,
  `height`, and `alt`.
- Use `next/link` (`<Link>`) for all internal and external anchors.

### Styling (Tailwind CSS 4)

- Tailwind is configured entirely in `app/globals.css` via `@theme {}` — there
  is no `tailwind.config.js`.
- Use utility classes directly in JSX; no CSS Modules or inline `style` objects
  unless unavoidable.
- Brand custom colors available: `text-moonpay` (`#7715F5`),
  `text-cosmos` / `hover:text-cosmos` (`#39107A`).

### Error Handling

The current codebase has no explicit error handling. When adding new features:

- Validate environment variables at startup (guard against `undefined`).
- Add `error.tsx` / `not-found.tsx` boundaries for user-facing errors.
- Wrap external I/O (DB queries, API calls) in `try/catch` and surface errors
  with appropriate HTTP status codes or UI feedback.
- Do **not** swallow errors silently.

---

## Project-Specific Notes

- **`prisma/generated/` is gitignored.** Always run `pnpm install` (or
  `pnpm exec prisma generate`) before building so the generated client exists.
- The Prisma client is a **global singleton** in `lib/prisma.ts` to survive
  Next.js hot reloads in development.
- `POSTGRES_PRISMA_URL` is the only required runtime environment variable.
- The `docker-compose.yaml` wires the `nextjs` service to
  `host.docker.internal:5432` — use `postgres` as the hostname when both
  containers are on the same Docker network instead.
- There is no `.prettierrc`; if you add one, document it here and update
  the formatting section above.
- There are no Cursor rules, Copilot instructions, or other agent config files
  in this repository beyond this file.

---

## Challenge Tasks

The goal is to **deploy the Next.js application in a production-ready manner**.

### Task 1: Containerize the Application

- Write a `Dockerfile` for the `nextjs` service (already referenced in
  `docker-compose.yaml` as `build: .`).
- Follow best practices for a Next.js application (multi-stage build, minimal
  image, non-root user, etc.).
- Build and run the container locally to verify it works.

**Key hints:**

- Add `output: "standalone"` to `next.config.ts` so Next.js emits a
  self-contained server bundle:

  ```ts
  const nextConfig: NextConfig = {
    output: "standalone",
  };
  ```

- `export const dynamic = "force-dynamic"` is already set in `app/page.tsx` to
  prevent database connections at build time — no build-time `POSTGRES_PRISMA_URL`
  is required in the Dockerfile.
- When both containers share the same Docker network, use `postgres` as the
  database hostname (not `host.docker.internal`).

### Task 2: Deploy the Application

Deploy the containerized application in a production-ready way. Kubernetes
(local or cloud) is strongly preferred, but other cloud platforms (Cloudflare,
AWS ECS, GCP Cloud Run, Fly.io, etc.) are acceptable.

The deployed solution should address:

- **Security** — least-privilege access, secrets management, no sensitive data
  baked into the image.
- **Scalability** — horizontal scaling, resource limits/requests.
- **Reliability** — health checks, restart policies, rolling updates.

The application must be reachable and return live cryptocurrency prices.
