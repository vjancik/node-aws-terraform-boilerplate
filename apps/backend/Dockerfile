# syntax=docker/dockerfile:1

FROM node:24-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
RUN apk add --no-cache libc6-compat

# Install all deps and build
FROM base AS build
ARG TARGETARCH
WORKDIR /app
# Copy manifests first so the install layer is cached independently of source changes
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/backend/package.json apps/backend/
RUN --mount=type=cache,id=pnpm-${TARGETARCH},target=/pnpm/store pnpm install --frozen-lockfile --filter @repo/backend...
COPY apps/backend/ apps/backend/
RUN pnpm --filter @repo/backend build
RUN --mount=type=cache,id=pnpm-${TARGETARCH},target=/pnpm/store pnpm deploy --filter @repo/backend --prod /prod/backend

# Final image
FROM node:24-alpine
ENV NODE_ENV=production
WORKDIR /prod/backend
COPY --from=build /prod/backend .
EXPOSE 3000
CMD ["node", "dist/main"]
