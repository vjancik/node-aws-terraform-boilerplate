import Link from "next/link"
import { headers } from "next/headers"
import { Button, buttonVariants } from "@/components/ui/button"
import { auth } from "@/lib/auth"
import { signOut } from "./actions/auth"

export default async function Home() {
  const session = await auth.api.getSession({ headers: await headers() })
  const user = session?.user

  return (
    <div className="flex min-h-svh flex-col">
      <nav className="flex items-center justify-between px-6 py-4">
        <Link href="/" className="font-semibold">
          Example Inc.
        </Link>
        <div className="flex items-center gap-2">
          {user ? (
            <>
              <div className="flex flex-col items-end text-sm">
                <span>Logged in as</span>
                <span className="text-muted-foreground">{user.email}</span>
              </div>
              <form action={signOut}>
                <Button variant="outline" type="submit">Sign Out</Button>
              </form>
            </>
          ) : (
            <>
              <Link href="/signup" className={buttonVariants({ variant: "outline" })}>
                Sign Up
              </Link>
              <Link href="/login" className={buttonVariants({ variant: "default" })}>
                Sign In
              </Link>
            </>
          )}
        </div>
      </nav>
      <main className="flex flex-1 flex-col items-center justify-center gap-6 text-center px-6">
        <div className="flex flex-col items-center gap-2">
          <h1 className="text-4xl font-semibold tracking-tight">
            {user ? `Welcome to our example app, ${user.name}!` : "Welcome to our example app!"}
          </h1>
          {!user && (
            <h2 className="text-2xl font-medium text-muted-foreground">Sign in to proceed.</h2>
          )}
        </div>
        {!user && (
          <Button asChild className="h-14 px-10 text-lg">
            <Link href="/login">Log In</Link>
          </Button>
        )}
      </main>
    </div>
  )
}
