import Link from "next/link"
import { Button, buttonVariants } from "@/components/ui/button"

export default function Home() {
  return (
    <div className="flex min-h-svh flex-col">
      <nav className="flex items-center justify-between px-6 py-4">
        <Link href="/" className="font-semibold">
          Example Inc.
        </Link>
        <div className="flex items-center gap-2">
          <Link href="/signup" className={buttonVariants({ variant: "outline" })}>
            Sign Up
          </Link>
          <Link href="/login" className={buttonVariants({ variant: "default" })}>
            Sign In
          </Link>
        </div>
      </nav>
      <main className="flex flex-1 flex-col items-center justify-center gap-6 text-center px-6">
        <div className="flex flex-col items-center gap-2">
          <h1 className="text-4xl font-semibold tracking-tight">Welcome to our example app!</h1>
          <h2 className="text-2xl font-medium text-muted-foreground">Sign in to proceed.</h2>
        </div>
        <Button asChild className="h-14 px-10 text-lg">
          <Link href="/login">Sign in</Link>
        </Button>
      </main>
    </div>
  )
}
