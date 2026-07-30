# Runtime Config

This document defines how runtime configuration is loaded and validated for Cloudflare Worker apps in this repo.

## Direction

- Read config from Cloudflare Worker env bindings (`env`) in server/runtime code.
- Validate env shape with Zod before use.
- Export inferred TypeScript types from the Zod schema so config stays type-safe end to end.
- Avoid `process.env` for Worker runtime logic.

## Where Config Lives

- `wrangler.jsonc` `vars` for non-secret values per environment.
- Wrangler secrets for sensitive values.
- App-local runtime schemas for typed access in code.

Current pattern in this repo:

- Keep an app-local `workerEnv.ts` in each app.
- Export a `WorkerEnv` Zod schema.
- Parse incoming Cloudflare `env` with that schema at runtime boundaries.

For `@chalkmd/app` CLI endpoints, configure a shared token as a Wrangler secret:

- key: `CLI_SHARED_TOKEN`
- usage: authorize `apps/cli` requests to `/_/cli/*`

## Validation Pattern

Use this shape in each app:

```ts
import { z } from 'zod'

export const WorkerEnv = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).optional(),
  API_BASE_URL: z.string().url(),
  CLERK_PUBLISHABLE_KEY: z.string().min(1),
})

export type WorkerEnv = z.infer<typeof WorkerEnv>
```

At runtime boundary:

```ts
const workerEnv = WorkerEnv.parse(env)
```

## Rules

- Validate once at the runtime boundary, then pass typed config inward.
- Keep schema keys aligned with Wrangler `vars` and secret names.
- Prefer narrow enums and constrained strings over broad `string` when possible.
- Keep app-specific bindings in that app's schema; do not centralize all app env in one global schema.
- Do not cast unknown env objects to `WorkerEnv`; always parse.

## Environment Separation

- `local`: use local dev env sources for Worker runtime.
- `stg` and `prd`: define env-specific `vars` and secrets via Wrangler.
- Keep required key sets consistent across `stg` and `prd` unless intentionally different.

See also:

- `references/platform.environments.md`
- `references/data.access.md`
- Active repository `AGENTS.md`, when present (TypeScript + Worker env rules)
