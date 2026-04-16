import "server-only"
import { cache } from "react"
import { headers } from "next/headers"
import { auth } from "@/lib/auth"

export const getUser = cache(async () => {
  const session = await auth.api.getSession({ headers: await headers() })
  return session?.user ?? null
})
