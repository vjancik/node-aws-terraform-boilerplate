import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { z } from "zod";
// biome-ignore lint/performance/noNamespaceImport: we always want all of them in this use-case
import * as schema from "./schema";

const { data, error } = z
  .object({ DATABASE_URL: z.string().min(1) })
  .safeParse(process.env);
if (error) {
  console.warn("DB env validation failed:\n", z.prettifyError(error));
}

// NOTE: Undefined at Next.js build time, but still invoked during route enumeration
export const db = drizzle({
  client: postgres(data?.DATABASE_URL ?? ""),
  schema,
});
