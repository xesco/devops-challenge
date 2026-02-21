# syntax=docker/dockerfile:1

# Stage 1: install dependencies and generate the Prisma client.
# Isolated so the node_modules layer is cached independently from source changes.
FROM node:22.22-alpine AS deps

# All stages use /app as the working directory
WORKDIR /app

# Pin pnpm to the version in pnpm-lock.yaml — avoids a runtime registry download
# and keeps the resolved version auditable.
RUN corepack enable && corepack prepare pnpm@10.30.1 --activate

# Copy only what affects dependency resolution to maximise cache reuse
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
# prisma/schema.prisma is required by `prisma generate` (runs via postinstall)
COPY prisma ./prisma

RUN pnpm install --frozen-lockfile


# Stage 2a: database migration image.
# Branches off deps — carries the Prisma CLI and migration SQL files but no
# application code. Used exclusively by the Kubernetes migration Job.
FROM node:22.22-alpine AS migrator

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.30.1 --activate

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./
COPY --from=deps /app/prisma ./prisma
COPY prisma.config.ts ./

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 --ingroup nodejs nextjs && \
    mkdir -p /app/.cache/corepack && chown nextjs:nodejs /app/.cache/corepack
ENV COREPACK_HOME=/app/.cache/corepack
USER nextjs

ENTRYPOINT ["pnpm", "exec", "prisma", "migrate", "deploy"]


# Stage 2b: compile the application.
# No database connection needed — `export const dynamic = "force-dynamic"` in
# app/page.tsx defers all DB access to request time.
FROM node:22.22-alpine AS builder

# All stages use /app as the working directory
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.30.1 --activate

# Suppress Next.js anonymous build telemetry — avoids outbound network calls
# during CI/CD builds and keeps build output clean
ENV NEXT_TELEMETRY_DISABLED=1

# Bring in the installed dependencies and generated Prisma client from deps
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/prisma/generated ./prisma/generated
# Copy application source
COPY . .

# output: "standalone" emits a trimmed node_modules subset under .next/standalone/
# so the runner stage needs no install step
RUN pnpm build


# Stage 3: minimal production image.
# Contains only the standalone server bundle, static assets, and the Node runtime.
FROM node:22.22-alpine AS runner

WORKDIR /app

# Runtime environment — HOSTNAME=0.0.0.0 binds the server on all interfaces
# inside the container; NEXT_TELEMETRY_DISABLED suppresses anonymous usage
# reporting at runtime
ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1

# Non-root user — least-privilege
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 --ingroup nodejs nextjs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
# Standalone intentionally omits static assets (to allow CDN offload);
# copy manually so the Node server can serve them directly
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# Drop privileges before starting the process
USER nextjs

# EXPOSE is metadata only — it does not publish the port.
# Actual port mapping is controlled by docker-compose.yaml or the orchestrator.
EXPOSE 3000

# HEALTHCHECK is only honoured by Docker and Docker Compose.
# Kubernetes ignores it in favour of livenessProbe/readinessProbe in the Pod spec.
# wget ships with Alpine; 127.0.0.1 used explicitly as BusyBox wget does not resolve `localhost`.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/ || exit 1

# Run the standalone server directly with Node — no shell wrapper or process manager needed
CMD ["node", "server.js"]
