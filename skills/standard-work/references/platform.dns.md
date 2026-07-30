# Routing Plan: Dual Domain

Goal: keep marketing (public, cacheable) and app (authenticated, dynamic) cleanly
separated on Cloudflare, while making marketing caching straightforward.

- Marketing: `hello.chalk.md`
- App: `chalk.md`

## Why dual domain

- No front-door router Worker required.
- Marketing responses can be aggressively cached at the edge (better hit rate).
- App can keep strict no-cache semantics for authenticated HTML.
- Operationally simple: each hostname maps directly to its deployment target.

## High-Level Diagram

```
User -----> hello.chalk.md ----> Marketing (TanStack Start)
User -----> chalk.md ---------> App (TanStack Start)
```

Both can be deployed as Cloudflare Workers (Wrangler), or marketing can move to
Cloudflare Pages (or another host) later without changing app routing.

## Cloudflare Notes

### DNS / hostnames

- Create two DNS records:
  - `hello.chalk.md` -> marketing deployment
  - `chalk.md` -> app deployment
- Keep TLS/SSL mode consistent across both hostnames.

### Caching strategy

Marketing (`hello.chalk.md`):

- Prefer cacheable HTML:
  - Avoid setting cookies on marketing pages.
  - Use `Cache-Control: public, s-maxage=...` (and optionally `stale-while-revalidate`).
- Static assets (JS/CSS/images):
  - Long-lived immutable caching (hashed filenames) and/or Cloudflare default asset caching.
- Use Cloudflare Cache Rules to:
  - Cache everything on marketing except truly dynamic endpoints.
  - Bypass cache on admin/preview routes if you add them later.

App (`chalk.md`):

- Authenticated HTML should be non-cacheable:
  - `Cache-Control: private, no-store` (or very short-lived) for logged-in HTML.
- APIs:
  - Cache only where safe (e.g. public metadata); prefer 401/403 JSON over redirects.

### Security / isolation benefits

- Marketing and app can have different WAF/rate-limit posture.
- You can apply stricter protections to `chalk.md` without affecting marketing performance.

## Cross-Domain UX

- Primary CTA buttons on marketing should link to the app domain:
  - Sign in: `https://chalk.md/sign-in`
  - Get started: `https://chalk.md/...`
- If you ever want a shared cookie across both subdomains, use a cookie domain of `.chalk.md`.
  Keep marketing cookie-free if possible to preserve caching.

## Future Option: One Domain (Front Door Router)

If you later decide you want a single hostname with clean URLs, add a small
front-door Worker that routes requests to marketing vs app (path allowlist +
auth checks). Dual-domain keeps that option open.
