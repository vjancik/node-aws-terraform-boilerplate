<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

### Styling and components rules
- Use Shadcn components for common reusable components, you can add them as `pnpm dlx shadcn@latest add <component> -c apps/web`
- Prefer Tailwind classes to custom style overrides.
- use `cn` from `@/lib/utils` for merging Tailwind conditional classes. 