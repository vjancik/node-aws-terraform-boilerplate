import { getAuth } from "@repo/db/auth";

export const auth = getAuth(true, process.env.NODE_ENV !== "production");
