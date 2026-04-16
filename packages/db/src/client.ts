import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { z } from "zod";
// biome-ignore lint/performance/noNamespaceImport: we always want all of them in this use-case
import * as schema from "./schema";

const envSchema = z.object({ DATABASE_URL: z.string().min(1) });

// Lazy singleton — defers env validation to first call so Next.js build doesn't
// require DATABASE_URL at static analysis time.
let env: z.infer<typeof envSchema> | undefined;
let db: ReturnType<typeof drizzle<typeof schema>> | undefined;

export function getDb() {
  env ??= envSchema.parse(process.env);
  db ??= drizzle({ client: postgres(env.DATABASE_URL), schema });
  return db;
}
