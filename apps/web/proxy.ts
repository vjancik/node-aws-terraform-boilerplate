import { NextRequest, NextResponse } from "next/server"
import { getSessionCookie } from "better-auth/cookies"

const GUEST_ONLY_URLS = ["/login", "/signup"]
// NOTE: only for demonstration, in a real app you'd likely have more complex rules around which authenticated users can access which pages
const AUTHENTICATED_ONLY_URLS = ["/dashboard"]

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl
  const sessionCookie = getSessionCookie(request)

  if (GUEST_ONLY_URLS.includes(pathname) && sessionCookie) {
    return NextResponse.redirect(new URL("/", request.nextUrl))
  }

  if (AUTHENTICATED_ONLY_URLS.some(url => pathname.startsWith(url)) && !sessionCookie) {
    return NextResponse.redirect(new URL("/login", request.nextUrl))
  }

  return NextResponse.next()
}

export const config = {
  // matcher: ["/login", "/signup", "/dashboard/:path*"],
  matcher: ['/((?!api|_next/static|_next/image|.*\\.png$).*)'],
}
