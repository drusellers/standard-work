# Clerk Integration Plan (`apps/app`)

This plan is based on the working Clerk integration in `browser-old`, adapted to the current monorepo structure and conventions in this repo.

## Workspace Configuration

We use a single Clerk workspace for all environments:

| Workspace      | Application | Clerk Env   | Our Environment |
|----------------|-------------|-------------|-----------------|
| A Curious Mind | Production  | Production  | 'prd'           |
| ...            | Not Prod    | Production  | 'stg'           |
| ...            | ...         | Development | 'dev' (local)   |

This maps our three deployment environments across two Clerk applications within one workspace.

## Scope

- Integrate Clerk auth into `apps/app` (TanStack Start + Cloudflare Workers).
- Keep `apps/marketing` public and mostly cookie-free.
- Align with existing auth direction in `references/auth.overview.md` (Clerk users/orgs mapped to internal auth tables).

## What `browser-old` Already Proved

From `/Users/drusellers/dev/chalkmd/browser-old`, the core auth pattern is:

1. `clerkMiddleware()` in `src/start.tsx` to parse Clerk session state per request.
2. `ClerkProvider` in `src/routes/__root.tsx` for client auth context/hooks/components.
3. Public auth routes (`/login`, `/signup`, `/login/sso-callback`) using Clerk components.
4. Protected layout gate via route `beforeLoad` + server auth check (`authStateFn`).
5. Server-side `auth()` and `clerkClient()` usage for identity-aware server functions.

These are the pieces we should carry forward.

## Current Repo Constraints To Respect

- TanStack Start server functions should live in `apps/app/src/server/*`.
- Cloudflare bindings/env should be validated with app-local `WorkerEnv` Zod schema.
- Prefer typed, schema-first boundaries; avoid `any`/casts.
- Use TanStack flat route conventions for route files.

## Implementation Plan

## 1) Dependencies and baseline wiring

- Add `@clerk/tanstack-react-start` to `apps/app/package.json`.
- Keep `apps/marketing` unchanged for now.
- If needed for dev optimization, add Clerk package to Vite optimize deps in `apps/app/vite.config.ts`.

Expected result: app builds with Clerk package available to both server and client code.

## 2) Environment + Worker binding model

- Extend `apps/app/workerEnv.ts` with Clerk vars used by runtime code (for example `CLERK_PUBLISHABLE_KEY`, `CLERK_SIGN_IN_URL`, optional post-auth redirects).
- Add non-secret per-env vars to `apps/app/wrangler.jsonc` under `vars` (`stg`/`prd`) where appropriate.
- Configure secrets (`CLERK_SECRET_KEY`) via Wrangler secrets, not checked into git.

Notes:

- Avoid `process.env` for app logic; prefer validated Worker env access.
- Keep auth env read logic centralized and typed.

### Secret handling (local vs remote)

For this repo's Cloudflare Worker setup, use Wrangler env sources instead of committed `.env` files.

- Local dev (`apps/app`): use an untracked `apps/app/.dev.vars` file.
- Remote envs (`stg`, `prd`): use Wrangler secrets for sensitive values.
- Keep only non-sensitive defaults in `wrangler.jsonc` `vars`.

Recommended split:

- `CLERK_SECRET_KEY`: secret (never committed)
- `CLERK_PUBLISHABLE_KEY`: not secret, but still environment-specific

Example local file (`apps/app/.dev.vars`):

```bash
CLERK_SECRET_KEY=sk_test_...
CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SIGN_IN_URL=/login
```

Example remote secret setup:

```bash
# from apps/app/
wrangler secret put CLERK_SECRET_KEY --env stg
wrangler secret put CLERK_SECRET_KEY --env prd
```

Notes:

- `.gitignore` already excludes `.dev.vars*`, so local secret files are not shared.
- If you prefer not to commit `CLERK_PUBLISHABLE_KEY` either, store it in `.dev.vars` and set it per remote env as a secret/var in Cloudflare.

## 3) Request middleware integration

- Update `apps/app/src/start.ts` to include Clerk middleware with existing logging middleware.
- Keep request logging middleware in the chain.

Recommended order:

- `requestLoggingMiddleware`
- `clerkMiddleware()`

Expected result: every request has Clerk auth context available to server functions.

## 4) Root provider integration

- Wrap app root in `ClerkProvider` inside `apps/app/src/routes/__root.tsx`.
- Preserve existing `UiPreferencesProvider` and document structure.

Expected result: client routes/components can use Clerk hooks/components (`useAuth`, `UserButton`, etc.).

## 5) Add auth surface routes

- Add flat-route files for:
  - `/login`
  - `/signup`
  - `/login/sso-callback`
- Add logout handling via:
  - `/logout` route that signs the user out and redirects to `/login`, or
  - UI-triggered Clerk sign-out action (for example, via `UserButton`) with explicit post-logout redirect.
- Render Clerk `SignIn`/`SignUp` components in those routes.
- Keep these routes public.

Expected result: complete Clerk sign-in/sign-up/sign-out flow from app domain.

## 6) Add server auth guard utilities

- Create `apps/app/src/server/auth/*` utilities for:
  - Require signed-in user (server-side)
  - Redirect unauthenticated requests to sign-in route
  - Optionally fetch Clerk backend user object when needed
- Use `auth()`/`clerkClient()` from Clerk server package in these utilities.
- Validate any custom session claim reads with Zod schemas.

Expected result: one reusable, typed auth gate for loaders/actions/server functions.

## 7) Protect application routes

- Introduce a protected route layout (flat-route layout pattern) that runs auth check in `beforeLoad`.
- Move app-private screens under that protected layout.
- Keep `robots.txt`, `sitemap.xml`, and auth pages outside protected layout.

Initial route target:

- Protect `/` and `/workouts/new`.

Expected result: unauthenticated users are redirected to `/login`; authenticated users can access app pages.

## 8) Connect identity to tenancy model

- Replace temporary `defaultAccountId` usage in server functions (for example `createWorkout`) with authenticated account resolution.
- Implement a session -> (`userId`, `accountId`, `role`) resolver in `apps/app/src/server/auth/`.
- Align resolution behavior with `references/auth.overview.md` and `references/data.multiTenancy.md`.

Expected result: data writes/reads are scoped by real authenticated tenant context.

## 9) Sync strategy (Clerk -> internal auth tables)

- Implement v1 bootstrap sync on authenticated session access:
  - upsert `auth.users` by `clerk_user_id`
  - upsert `auth.accounts` by `clerk_org_id`
  - upsert membership rows
- Add webhook-driven sync later for stronger consistency.

Expected result: app authorization works from internal tables while Clerk remains identity source of truth.

## 10) Verification checklist

- Unauthenticated request to protected route redirects to `/login`.
- Successful login returns to app and protected loader/action calls succeed.
- Logout clears session and redirects to `/login` (or configured public landing page).
- Server functions can read authenticated user id from Clerk server auth context.
- Workout create/list operates using resolved `accountId`, not hardcoded default.
- Staging and production have correct Clerk keys/secrets configured.

## Migration Notes from `browser-old`

- Reuse the proven pattern (`start` middleware + root provider + auth routes + protected layout).
- Do not port `process.env`-based auth redirects directly; use Worker env schema + helpers.
- Do not rely on raw cookie parsing for normal auth checks; prefer Clerk `auth()` server API.
- Keep all server auth utilities in `apps/app/src/server/` (not inside route files).

## Suggested Rollout Phases

1. Baseline auth plumbing (steps 1-7) behind a small PR.
2. Tenant/account resolution and removal of hardcoded account id (step 8).
3. Internal table synchronization and webhook hardening (step 9).
