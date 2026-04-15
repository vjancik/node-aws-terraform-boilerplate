# Web App TODO

## Auth & Security

- [x] **Form state and status** — add loading states and disable submit buttons while pending to prevent double submits; show field-level validation errors
- [x] **Proxy middleware** — add `proxy.ts` for optimistic session checks, redirect unauthenticated users away from protected routes and authenticated users away from `/login`/`/signup`
- [ ] **Session and cookie config** — review expiry, `sameSite`, `secure` settings in better-auth config; see performance guide TODO in `packages/db/src/auth.ts`
- [ ] **Protected app functionality** — build out signed-in routes with server actions gated behind [safe-next-action](https://next-safe-action.dev/) middleware for type-safe, authorized mutations
- [ ] **Generate OpenAPI docs for Better Auth endpoints** - Enabled with https://better-auth.com/docs/plugins/open-api. Needed for external clients (mobile / apps in other languages without client SDKs)

## next-themes

- [ ] Wire up `next-themes` `ThemeProvider` and switch `@custom-variant dark` in `globals.css` to class-only (remove `@media` fallback)

## Optional / Nice to have

- [ ] **Animations and page transitions** — add motion primitives or Framer Motion for page/route transitions and micro-interactions
- [ ] **Login modal** — show sign in form in a modal from the root page instead of redirecting to `/login`
