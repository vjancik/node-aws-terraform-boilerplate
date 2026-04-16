import Link from "next/link"
import { Button } from "@/components/ui/button"
import { getUser } from "@/lib/dal"
import NavBar from "@/components/nav-bar"

export default async function Home() {
  const user = await getUser()

  return (
    <div className="flex min-h-svh flex-col">
      <NavBar />
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
            <Link href="/login">Sign In</Link>
          </Button>
        )}
      </main>
    </div>
  )
}
