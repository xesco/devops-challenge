# syntax=docker/dockerfile:1

# Stage 1: install dependencies and generate the Prisma client
# Isolated so the node_modules layer is cached independently from source changes
FROM node:22.22-alpine AS deps
WORKDIR /app

# Copy package.json first so corepack can read the packageManager field
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# pnpm version is read from packageManager field in package.json - single source of truth
RUN corepack enable && corepack prepare --activate

# prisma/schema.prisma is required by `prisma generate` (runs via postinstall)
COPY prisma ./prisma

RUN pnpm install --frozen-lockfile


# Stage 2a: migration image - Prisma CLI + migration SQL, no application code
# Used exclusively by the Kubernetes migration Job
FROM node:22.22-alpine AS migrator
WORKDIR /app

# node_modules from deps already contains the prisma binary - no need to reinstall pnpm
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/prisma ./prisma
COPY prisma.config.ts ./

# Drop to built-in non-root user
USER node
ENTRYPOINT ["node_modules/.bin/prisma", "migrate", "deploy"]


# Stage 2b: build the application
# No DB connection needed - `export const dynamic = "force-dynamic"` defers all queries to request time
FROM node:22.22-alpine AS builder
WORKDIR /app

# Suppress Next.js anonymous build telemetry
ENV NEXT_TELEMETRY_DISABLED=1

# Bring in installed dependencies and generated Prisma client from deps
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/prisma/generated ./prisma/generated

# Copy application source (includes package.json with packageManager field)
COPY . .

# output: "standalone" emits a self-contained server bundle under .next/standalone/
RUN node_modules/.bin/next build


# Stage 3: minimal production image with standalone server bundle, static assets, and Node runtime
FROM node:22.22-alpine AS runner
WORKDIR /app

# HOSTNAME=0.0.0.0 binds on all interfaces; telemetry disabled at runtime too
ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1

# Non-root user for least-privilege
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 --ingroup nodejs nextjs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
# Standalone omits static assets (for CDN offload); copy for self-hosted serving
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# Drop privileges
USER nextjs

# EXPOSE is metadata only - actual port mapping is controlled by the orchestrator
EXPOSE 3000

# Docker/Compose only - K8s uses livenessProbe/readinessProbe instead
# whether the Node process is alive, not whether the database is reachable
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/healthz || exit 1

# Run the standalone server directly with Node
CMD ["node", "server.js"]
