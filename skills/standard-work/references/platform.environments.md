# Environments and Deployment

This repo runs two TanStack Start apps on Cloudflare Workers:

- Marketing (public, cacheable)
- App (authenticated, dynamic)

Dual-domain routing is the default model. We do not use a front-door router Worker.

## Environment Progression

- `local`: fastest iteration on your machine
- `stg`: stable pre-production environment for QA and demos
- `prd`: public production environment

Optional:

- PR preview: ephemeral Workers on `*.workers.dev` (no stable custom domains)

## Naming Rules (Required)

Use these names consistently in Wrangler, scripts, and CI:

- Environment keys: `stg`, `prd`
- Wrangler env blocks: `env.stg`, `env.prd`
- Worker service suffixes: `-stg`, `-prd`
- Script names: `deploy:stg`, `deploy:prd`

Avoid these for environment keys: `stage`, `staging`, `prod`, `production`.

## App and Domain Mapping

Marketing app:

- local: `@chalkmd/marketing` via `http://localhost:3001`
- stg worker: `chalkmd-marketing-stg` -> `hello.staging.chalk.md`
- prd worker: `chalkmd-marketing-prd` -> `hello.chalk.md`

App:

- local: `@chalkmd/app` via `http://localhost:3000`
- stg worker: `chalkmd-app-stg` -> `staging.chalk.md`
- prd worker: `chalkmd-app-prd` -> `chalk.md`

## Wrangler Conventions

Each app has its own Wrangler config:

- `apps/marketing/wrangler.jsonc`
- `apps/app/wrangler.jsonc`

Each env block should define:

- `name`
- `workers_dev`
- `routes` with `custom_domain: true` when using custom hostnames
- `vars`
- env-specific bindings and secrets

Deploy explicitly per environment:

- `wrangler deploy --env stg`
- `wrangler deploy --env prd`

Avoid bare `wrangler deploy` for normal stg/prd workflows.

## Deploy Commands (Repo Root)

- `npm run deploy:stg`
- `npm run deploy:prd`

These should call app-level scripts that also use `--env stg` and `--env prd`.

## Cloudflare Dashboard Verification

Look in Cloudflare Dashboard -> Workers & Pages -> Workers.

You should see services like:

- `chalkmd-marketing-stg`
- `chalkmd-marketing-prd`
- `chalkmd-app-stg`
- `chalkmd-app-prd`

Open each Worker and verify Triggers/Routes include the expected custom domains.

## DNS and Custom Domains

- DNS records must exist in the `chalk.md` zone for each hostname.
- Routes/domains are attached per deployed Worker service (`*-stg`, `*-prd`).
- If a domain is missing, verify you deployed the right env and inspect that Worker service in the dashboard.

## Local Development

Use local dev servers for fast feedback:

- `npm run dev:marketing`
- `npm run dev:app`

Use Wrangler local runtime only when you need Cloudflare-specific behavior (bindings, headers, cache semantics).

## Caching and Cross-Domain Guidance

Marketing (`hello.*`):

- Keep pages cookie-free where possible.
- Prefer cacheable HTML: `Cache-Control: public, s-maxage=...`.
- Use immutable caching for hashed static assets.

App (`chalk.*`):

- Authenticated HTML: `Cache-Control: private, no-store`.
- APIs: cache only where safe; prefer 401/403 JSON for auth failures.

CTA links from marketing should be environment-aware:

- prd sign-in: `https://chalk.md/sign-in`
- stg sign-in: `https://staging.chalk.md/sign-in`

If shared cookies are ever needed:

- prd cookie domain: `chalk.md`
- stg cookie domain: `staging.chalk.md`

For cache performance, keep marketing cookie-free whenever possible.

## Checklist for New Worker Services

1. Add `env.stg` and `env.prd` blocks.
2. Set worker names with `-stg` and `-prd` suffixes.
3. Define env-specific routes or custom domains.
4. Add root scripts for `deploy:stg` and `deploy:prd`.
5. Add DNS records for staging and production hostnames.
6. Verify both services appear in Cloudflare dashboard after deploy.
