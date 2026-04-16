import Image from "next/image";
import Link from "next/link";
import { signOut } from "@/app/actions/auth";
import { ModeToggle } from "@/components/mode-toggle";
import { Button, buttonVariants } from "@/components/ui/button";
import { getUser } from "@/lib/dal";

export default async function NavBar() {
  const user = await getUser();

  return (
    <nav className="flex items-center justify-between px-6 py-4">
      <Link className="flex items-center gap-2 font-semibold" href="/">
        <Image
          alt="Vercel logo"
          className="invert dark:invert-0"
          height={24}
          src="/vercel.svg"
          width={24}
        />
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
              <Button type="submit" variant="outline">
                Sign Out
              </Button>
            </form>
          </>
        ) : (
          <>
            <Link
              className={buttonVariants({ variant: "outline" })}
              href="/signup"
            >
              Sign Up
            </Link>
            <Link
              className={buttonVariants({ variant: "default" })}
              href="/login"
            >
              Sign In
            </Link>
          </>
        )}
        <ModeToggle />
      </div>
    </nav>
  );
}
