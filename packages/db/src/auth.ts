import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { betterAuth } from "better-auth/minimal";
import { nextCookies } from "better-auth/next-js";
import { z } from "zod";
import { getDb } from "./client";

// NOTE: rate limiting — Better Auth's built-in rateLimit only applies to client-side API
// routes (/api/auth/*). Server actions and server-side API routes bypass it entirely and
// need their own rate limiting (e.g. per-route middleware, Upstash Ratelimit, or an edge
// layer). The defaults below also need tuning for production traffic patterns.
// https://better-auth.com/docs/concepts/rate-limit
//
// TODO: review performance optimizations before going to production
// https://better-auth.com/docs/guides/optimizing-for-performance
// NOTE: email/password accounts do NOT link to existing SSO accounts (Google, GitHub, Discord)
// because email verification is not implemented. Without it, anyone could register with another
// user's email and get linked to their SSO account.
//
// To enable linking:
//   1. Add a transactional email provider (e.g. Resend, Postmark)
//   2. Set emailAndPassword.requireEmailVerification: true
//   3. Implement emailAndPassword.sendVerificationEmail: async ({ user, url }) => { ... }
const envSchema = z.object({
  GITHUB_CLIENT_ID: z.string().min(1),
  GITHUB_CLIENT_SECRET: z.string().min(1),
  GOOGLE_CLIENT_ID: z.string().min(1),
  GOOGLE_CLIENT_SECRET: z.string().min(1),
  DISCORD_CLIENT_ID: z.string().min(1),
  DISCORD_CLIENT_SECRET: z.string().min(1),
});

let env: z.infer<typeof envSchema> | undefined;

export function getAuth(nextApp = false) {
  env ??= envSchema.parse(process.env);

  return betterAuth({
    database: drizzleAdapter(getDb(), {
      provider: "pg",
    }),
    experimental: { joins: true },
    emailAndPassword: {
      enabled: true,
      // TODO: switch to Argon2id before going to production — default scrypt stores hashes as plain
      // `salt:hash` hex with no algorithm or params embedded, meaning scrypt config changes will
      // break verification of existing hashes. Argon2id uses PHC format which is self-describing.
      // Install @node-rs/argon2 and configure:
      // password: {
      //   hash: (password) => hash(password, { memoryCost: 65536, timeCost: 3, parallelism: 4, outputLen: 32, algorithm: 2 }),
      //   verify: ({ hash: h, password }) => verify(h, password, { algorithm: 2 }),
      // }
    },
    socialProviders: {
      github: {
        clientId: env.GITHUB_CLIENT_ID,
        clientSecret: env.GITHUB_CLIENT_SECRET,
      },
      google: {
        clientId: env.GOOGLE_CLIENT_ID,
        clientSecret: env.GOOGLE_CLIENT_SECRET,
      },
      discord: {
        clientId: env.DISCORD_CLIENT_ID,
        clientSecret: env.DISCORD_CLIENT_SECRET,
      },
    },
    ...(nextApp && {
      plugins: [nextCookies()],
    }),
  });
}
