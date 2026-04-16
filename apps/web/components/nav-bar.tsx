import Link from "next/link"
import Image from "next/image"
import { Button, buttonVariants } from "@/components/ui/button"
import { getUser } from "@/lib/dal"
import { signOut } from "@/app/actions/auth"
import { ModeToggle } from "@/components/mode-toggle"

export default async function NavBar() {
  const user = await getUser()

  return (
    <nav className="flex items-center justify-between px-6 py-4">
      <Link href="/" className="flex items-center gap-2 font-semibold">
        <Image src="/vercel.svg" alt="Vercel logo" width={24} height={24} className="invert dark:invert-0" />
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
        <ModeToggle />
      </div>
    </nav>
  )
}
