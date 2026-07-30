# Marketing SEO

## Goals

- Keep metadata setup simple and consistent across both TanStack Start apps.
- Centralize reusable SEO logic in app-local `src/seo.ts` modules.
- Always emit production canonical URLs, even when rendering staging.

## Product Positioning

- Messaging should target fitness trainers, including college strength coaches and personal trainers.
- Core value proposition: design and manage training programs with structured workflows.
- Optional AI value proposition: connect to a remote LLM service for deeper training detail and program refinement.
- SEO titles, descriptions, and social metadata should reinforce this positioning consistently.

## Current Setup

Marketing app (`apps/marketing`):

- Root metadata defaults are defined in `apps/marketing/src/routes/__root.tsx`.
- Home page metadata is defined via `buildMarketingSeoHead` in `apps/marketing/src/routes/index.tsx`.
- Shared SEO helper and canonical origin are in `apps/marketing/src/seo.ts`.
- Canonical origin is fixed to production: `https://hello.chalk.md`.

App surface (`apps/app`):

- Root metadata defaults are defined in `apps/app/src/routes/__root.tsx`.
- Home page metadata is defined via `buildAppSeoHead` in `apps/app/src/routes/index.tsx`.
- Shared SEO helper and canonical origin are in `apps/app/src/seo.ts`.
- Canonical origin is fixed to production: `https://chalk.md`.

Robots + sitemap:

- Marketing serves `GET /robots.txt` from `apps/marketing/src/routes/robots[.]txt.ts`.
- Marketing serves `GET /sitemap.xml` from `apps/marketing/src/routes/sitemap[.]xml.ts`.
- App serves `GET /robots.txt` from `apps/app/src/routes/robots[.]txt.ts`.
- App serves `GET /sitemap.xml` from `apps/app/src/routes/sitemap[.]xml.ts`.
- Route filenames escape dots (`[.]`) so TanStack file routing maps to literal dot paths.

## Metadata Pattern

For route-level SEO in TanStack Start, prefer route `head` functions:

- Set site-level defaults in `__root.tsx` (`charset`, `viewport`, base description, social defaults).
- Set page-specific `title`, `description`, Open Graph, Twitter, and canonical links in each route.
- Use app-local SEO helpers (`buildMarketingSeoHead`, `buildAppSeoHead`) to avoid drift.

## Canonical Policy

- Canonical links should always reference the production hostname.
- Staging pages should still render production canonical values to avoid duplicate indexing.
- Use root route canonical as a baseline, and route-level canonical for page-specific paths.
- Sitemap URLs and robots `Sitemap:` entries should use production origins.

## Adding A New SEO-Managed Page

1. Add a route file in `src/routes/`.
2. Add `head: () => build...SeoHead({ title, description, path })` in that route.
3. Use a canonical `path` that matches the public production URL path.
4. If needed, extend `src/seo.ts` with extra fields (e.g. `robots`, structured data).
