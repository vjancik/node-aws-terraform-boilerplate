# @repo/db

Shared database package. Provides a Drizzle ORM client, schema definitions, and migration tooling. Used by `apps/backend` and any other package that needs direct database access.

## Stack

- [Drizzle ORM](https://orm.drizzle.team/) — query builder and schema definition
- [drizzle-kit](https://orm.drizzle.team/kit-docs/overview) — migration generation and studio
- [better-auth](https://www.better-auth.com/) — auth schema and session management
- `postgres` — PostgreSQL driver

## Usage

Import the client and schema from other packages:

```ts
import { db } from '@repo/db';
import { users } from '@repo/db';
```

## Environment

Requires a `DATABASE_URL` environment variable:

```
DATABASE_URL=postgresql://migrator:migratorpassword@localhost:5438/app
```

For local development this is provided by `docker-compose.local.yaml`. See the root README for setup steps.

## Scripts

All scripts should be run from the **monorepo root** using `--filter`:

```bash
# Generate a new migration from schema changes
pnpm --filter @repo/db db:generate

# Apply pending migrations
pnpm --filter @repo/db db:migrate

# Open Drizzle Studio (runs on http://localhost:4983 by default)
pnpm --filter @repo/db db:studio
```

The `db:migrate` script is also what runs inside the `Dockerfile.migrator` container at deploy time.

## Structure

```
src/
  client.ts       # Drizzle client instance
  schema.ts       # application table definitions (add your tables here)
  auth.ts         # better-auth instance
  auth-schema.ts  # better-auth generated schema
  index.ts        # public exports
drizzle.config.ts
Dockerfile.migrator
```
