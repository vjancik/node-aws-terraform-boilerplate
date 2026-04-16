import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { z } from "zod";
// biome-ignore lint/performance/noNamespaceImport: we always want all of them in this use-case
import * as schema from "./schema";

const { DATABASE_URL } = z
  .object({
    DATABASE_URL: z.string().min(1),
  })
  .parse(process.env);

const client = postgres(DATABASE_URL);

export const db = drizzle({ client, schema });
