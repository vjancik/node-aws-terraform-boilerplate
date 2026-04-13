# Web App TODO

## Auth & Security

- [ ] **Form state and status** — add loading states and disable submit buttons while pending to prevent double submits; show field-level validation errors
- [ ] **Proxy middleware** — add `proxy.ts` for optimistic session checks, redirect unauthenticated users away from protected routes and authenticated users away from `/login`/`/signup`
- [ ] **Session and cookie config** — review expiry, `sameSite`, `secure` settings in better-auth config; see performance guide TODO in `packages/db/src/auth.ts`
- [ ] **Protected app functionality** — build out signed-in routes with server actions gated behind [safe-next-action](https://next-safe-action.dev/) middleware for type-safe, authorized mutations
- [ ] **Expose better-auth route handlers** — review which better-auth API endpoints need to be accessible (e.g. session, OAuth callbacks) and ensure they are correctly exposed via `app/api/auth/[...all]/route.ts`

## next-themes

- [ ] Wire up `next-themes` `ThemeProvider` and switch `@custom-variant dark` in `globals.css` to class-only (remove `@media` fallback)

## Optional / Nice to have

- [ ] **Animations and page transitions** — add motion primitives or Framer Motion for page/route transitions and micro-interactions
- [ ] **Login modal** — show sign in form in a modal from the root page instead of redirecting to `/login`
