# Monorepo Proposal (ChalkMD)

This repo will host two TanStack Start apps (marketing + application), one Cloudflare message worker app, and a set of shared packages under the NPM scope `@chalkmd/*`.

## Goals

- Two deployable sites: marketing + app, both TanStack Start.
- One deployable background processing worker: queue consumer + scheduled dispatcher.
- Shared React code: UI components (ShadCN), Tailwind v4 design tokens, utilities, and typed API boundaries.
- Cloudflare-friendly deployment with a dual-domain routing model that makes marketing caching straightforward.
- Cloudflare Queues-based async processing while keeping Postgres as system of record.

## Recommended Tooling

- Package manager: `npm` workspaces.
- Task runner: `nx` for cached builds/tests.
- TypeScript project references (optional) + per-package `tsconfig.json` extending a shared base.

## Proposed Directory Layout

```
.
├─ apps/
│  ├─ marketing/                 # TanStack Start marketing site
│  │  ├─ package.json            # name: @chalkmd/marketing (private)
│  │  ├─ wrangler.jsonc          # deploy marketing worker
│  │  └─ src/
│  ├─ app/                       # TanStack Start application site
│  │  ├─ package.json            # name: @chalkmd/app (private)
│  │  ├─ wrangler.jsonc          # deploy app worker
│  │  └─ src/
│  └─ jobs-worker/               # Cloudflare Worker for queue consume/dispatch
│     ├─ package.json            # name: @chalkmd/jobs-worker (private)
│     ├─ wrangler.jsonc          # queue bindings + cron triggers
│     └─ src/
│
├─ packages/
│  ├─ design-system/             # ShadCN components + Tailwind v4 tokens/config
│  │  ├─ package.json            # name: @chalkmd/design-system
│  │  ├─ components.json         # shadcn config (single source of truth)
│  │  ├─ src/components/
│  │  ├─ src/styles/             # tokens, globals, app-entry css
│  │  └─ src/index.ts
│  ├─ config/                    # Shared configs (tsconfig/eslint/prettier)
│  │  ├─ package.json            # name: @chalkmd/config
│  │  ├─ tsconfig/base.json
│  │  └─ eslint/
│  ├─ core/                      # Cross-cutting utilities (no UI)
│  │  ├─ package.json            # name: @chalkmd/core
│  │  └─ src/
│  ├─ jobs/                      # Shared job names, payload schemas, helpers
│  │  ├─ package.json            # name: @chalkmd/jobs
│  │  └─ src/
│  └─ api/                       # Typed API client/contracts (optional)
│     ├─ package.json            # name: @chalkmd/api
│     └─ src/
│
│
├─ tooling/
│  └─ scripts/                   # Release/build scripts if needed
│
├─ package.json                  # workspace root
├─ package-lock.json             # workspace lockfile
├─ nx.json
└─ tsconfig.json                 # references (or thin root config)
```

Notes:

- `apps/*` are deployables and typically remain `private: true`.
- `packages/*` are reusable libraries. Some can be published to NPM, or kept private.

## Package Naming Conventions

- Apps (private): `@chalkmd/marketing`, `@chalkmd/app`, `@chalkmd/jobs-worker`.
- Libraries: `@chalkmd/design-system`, `@chalkmd/core`, `@chalkmd/jobs`, `@chalkmd/api`.

If you plan to publish some packages later:

- Keep public-ready packages dependency-light and framework-agnostic (e.g. `@chalkmd/core`, `@chalkmd/api`).
- Keep app-specific code in `apps/*`.

## Shared Design System (ShadCN + Tailwind v4)

Recommended approach: a single shared package that owns components + styling.

- Run ShadCN generation into `packages/design-system`.
- Put Tailwind v4 tokens/config and shared CSS in `packages/design-system`.
- Export components from `packages/design-system/src/index.ts`.
- Both apps depend on `@chalkmd/design-system`.

Why this works well:

- One place to update component implementations.
- Consistent styling, variants, and accessibility.

Common pitfall to avoid:

- Duplicating ShadCN components per app (drifts quickly).

### Design system docs (Storybook vs a real site)

Yes: keep Storybook owned by the design-system package.

- Put Storybook config alongside the components (e.g. `packages/design-system/.storybook/`).
- Treat it as a dev/QA surface for components, tokens, and density modes.

If you want a full “design system website” (docs, guides, content, examples), make it a separate app.

- Add `apps/design-system` (or `apps/ds-site`) as a deployable TanStack Start site that depends on `@chalkmd/design-system`.
- This keeps the package focused on reusable code, while the site can have routes, MDX/content, search, and its own deployment.

### Handling spacing differences (marketing vs app)

Use a global "density" switch via CSS variables.

- Define semantic spacing/component geometry tokens as CSS variables (gaps, paddings, control height).
- Provide two density modes:
  - Marketing: comfortable spacing
  - App: compact spacing
- Set the mode at the app root (`data-density="comfortable"` vs `data-density="compact"`). Components read from the variables and reflow automatically.

Use per-component variants only for exceptions (e.g. an intentionally oversized marketing hero card).

## Tailwind v4 Strategy

Tailwind v4 tends to push you toward “CSS-first” configuration (tokens + layers)
instead of heavy JS presets. The simplest monorepo approach is to centralize the
design tokens + shared CSS in the design-system package.

Recommended shape:

- `packages/design-system/src/styles/` holds:
  - shared tokens (colors, radius, typography)
  - shared base/component layers
  - any globals both apps should share
- Each app imports the shared CSS entry from `@chalkmd/design-system` and adds only app-specific CSS on top.

This keeps:

- Design tokens centralized (colors, radius, typography scale, shadows).
- Styling consistent across both sites.

## TypeScript Strategy

- `packages/config/tsconfig/base.json` defines shared compiler options.
- Each package/app has a `tsconfig.json` extending the base.
- For app-local code, use the alias pattern `@/* -> src/*` to avoid deep relative imports.
- Use `exports` in each package `package.json` (ESM-first) to make imports explicit and stable.

Example import style:

- `import { Button } from "@chalkmd/design-system"`
- `import { cx } from "@chalkmd/core"`
- `import { requestLoggingMiddleware } from "@/server/requestLoggingMiddleware"`

## TanStack Start App Boundaries

Each app owns its:

- Routes/pages and route loaders/actions.
- Deployment config (`wrangler.jsonc`) and environment bindings.
- App shell (document, root layout) and any truly app-specific components.

Shared packages should avoid importing from `apps/*`.

## Queue Worker Boundaries (Cloudflare)

`apps/jobs-worker` owns its:

- Queue consumers (`queue()` handlers) and retry/dead-letter handling policy.
- Scheduled dispatcher (`scheduled()` handler) for outbox -> queue publish.
- Worker bindings and trigger config (`wrangler.jsonc` queue + cron config).

Recommended split of responsibilities:

- `apps/app`: write business state to Postgres and create outbox rows.
- `apps/jobs-worker`: publish pending outbox records to Queue and process Queue messages.
- `packages/jobs`: shared job ids, payload schemas (e.g. Zod), and idempotency helpers.

## Local Dev Workflow

Root scripts (illustrative):

- `npm run dev` runs both apps in parallel.
- `npm run dev:marketing`, `npm run dev:app` run individually.
- `npm run dev:jobs-worker` runs the queue/scheduled worker locally.
- `npm test` runs `vitest` across workspaces.
- `npm run build` builds all packages + apps.

With Nx, you typically model pipelines:

- `lint`, `typecheck`, `test` as workspace-wide tasks.
- `build` depends on upstream package builds.

## Deployment Model (Cloudflare)

Decision: dual domain.

- Marketing: `hello.chalk.md` -> `apps/marketing`
- App: `chalk.md` -> `apps/app`
- Background jobs: Cloudflare Queue -> `apps/jobs-worker` (no public hostname required)

Why:

- No front-door router Worker required.
- Marketing can be aggressively cached at the edge.
- App can keep strict no-cache semantics for authenticated HTML.

Cloudflare notes:

- DNS: create two hostnames and point each to its deployment target.
- Caching: keep marketing cookie-free where possible; set `Cache-Control: public, s-maxage=...` for marketing HTML; keep app authenticated HTML `private, no-store`.
- Security: apply stricter protections to `chalk.md` without impacting marketing performance.

Queue + worker notes:

- Prefer Postgres-backed outbox pattern for reliable enqueue.
- Keep Queue messages small and schema-validated.
- Make consumers idempotent (job id uniqueness in Postgres).

## What Stays Where (Rule of Thumb)

- `packages/design-system`: anything visual + shared styling/tokens.
- `packages/core`: pure functions, data helpers, small utilities.
- `packages/jobs`: queue message schemas, job constants, idempotency utilities.
- `packages/api`: request clients, types, and contracts.
- `apps/marketing`, `apps/app`: routes, loaders/actions, app-specific composition, deployment config.
- `apps/jobs-worker`: queue consumers, scheduled dispatchers, worker-level background orchestration.

## Migration From Single-App Repo

If this repo currently contains a single TanStack Start app at the root, the usual move is:

- Move current app into `apps/app` (or `apps/marketing`, whichever it is).
- Create `apps/marketing` as the second Start app.
- Extract shared UI/styling into `packages/design-system` once you have a second consumer.
