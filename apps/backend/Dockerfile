# syntax=docker/dockerfile:1

FROM node:24-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

# Install all deps and build
FROM base AS build
COPY . /app
WORKDIR /app
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --filter @repo/backend...
RUN pnpm --filter @repo/backend build
RUN pnpm deploy --filter @repo/backend --prod --legacy /prod/backend

# Final image
FROM node:24-alpine
ENV NODE_ENV=production
WORKDIR /prod/backend
COPY --from=build /prod/backend .
EXPOSE 3000
CMD ["node", "dist/main"]
