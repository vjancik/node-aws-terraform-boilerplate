# syntax=docker/dockerfile:1

FROM node:24-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
RUN apk add --no-cache libc6-compat

# ── Install dependencies & build ───────────────────────────────────────────────

FROM base AS builder
ARG TARGETARCH
WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/ apps/web/
COPY packages/db/ packages/db/

RUN --mount=type=cache,id=pnpm-${TARGETARCH},target=/pnpm/store pnpm install --frozen-lockfile --filter @repo/web...

# .env.public contains NEXT_PUBLIC_* vars baked into the client bundle at build time
COPY apps/web/.env.public apps/web/.env.public

RUN pnpm --filter @repo/web build

# ── Production image ───────────────────────────────────────────────────────────

FROM node:24-alpine AS runner
ENV NODE_ENV=production

RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# Standalone output preserves the monorepo structure — server.js lives at apps/web/server.js
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/.next/standalone /app
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/public /app/apps/web/public
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/.next/static /app/apps/web/.next/static

WORKDIR /app/apps/web
USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
CMD ["node", "server.js"]
