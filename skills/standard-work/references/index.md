# Standard Work Reference Index

Use this file as the routing layer for the `standard-work` skill. Read only the files needed for the current task.

## Read Order

1. `SKILL.md` for lazy-loading workflow and common entry points.
2. This index for task-to-reference routing.
3. Specific reference files listed below.

## Prefix Taxonomy

- `organization.*`: repository and codebase structure decisions.
- `platform.*`: infrastructure, environment, deployment, and DNS guidance.
- `runtime.*`: application runtime behavior inside services.
- `data.*`: data modeling, access patterns, and tenant data boundaries.
- `packages.*`: package-specific implementation notes and practical usage references.
- `marketing.*`: marketing strategy and marketing-adjacent implementation details.
- `auth.*`: authentication and identity-provider integration guidance.
- `codeStyle.*`: code-level conventions, API shape, defaults, and variant-state design.
- `change.*`: long-form change notes and historical architecture designs.

When a new doc does not clearly fit one of these prefixes, prefer extending an existing doc before creating a new top-level category.

## Task-To-Reference Map

### Architecture and repository organization

- Monorepo layout and package boundaries: `references/organization.monorepo.md`
- Feature-slice organization: `references/organization.featureSlice.md`
- Data movement through layers: `references/organization.dataPaths.md`
- Route and URL strategy: `references/organization.routes.md`
- CLI interface catalog: `references/organization.interfaces.cli.md`
- HTTP interface catalog and pagination contract: `references/organization.interfaces.http.md`

### Code style and API design

- TypeScript style conventions: `references/codeStyle.typescript.md`
- Cross-language design principles, defaults, and variant states: `references/codeStyle.designPrinciples.md`
- CLI command usage examples: `references/cli.usage.md`

### Runtime behavior

- Runtime logging conventions and middleware shape: `references/runtime.logging.md`
- Runtime configuration with Cloudflare env and Zod: `references/runtime.config.md`
- Runtime dependency injection and context composition: `references/runtime.dependencyInjection.md`
- Runtime AI patterns, prompts, caching, JSON output: `references/runtime.ai.md`
- Runtime streaming and SSE patterns: `references/runtime.streaming.md`
- Runtime testing conventions with Vitest and test types: `references/runtime.testing.md`

### Data and auth

- Data model conventions and shared primitives: `references/data.models.md`
- Data access and DB conventions: `references/data.access.md`
- Multi-tenant data model strategy: `references/data.multiTenancy.md`
- Authentication direction and account model: `references/auth.overview.md`
- Clerk implementation plan: `references/auth.clerk.md`

### Platform and operations

- Environment naming, staging workflow, and deploy conventions: `references/platform.environments.md`
- DNS and routing model: `references/platform.dns.md`

### Packages and frameworks

- Effection patterns and lifecycle guidance: `references/packages.effection.md`
- TanStack Start server function patterns: `references/packages.tanstackStart.md`
- TanStack Query integration notes: `references/packages.tanstackQuery.md`

### UI, marketing, and SEO

- Shared UI/tokens/component rules: `references/design-system.md`
- UI design principles for layout and composition: `references/design.principles.md`
- Marketing direction and typography: `references/marketing.md`
- SEO metadata and canonical conventions: `references/marketing.seo.md`

### Change notes and archive process

- AI architecture change note: `references/change.ai.md`
- Workout generation architecture change note: `references/change.workoutGeneration.md`
- Change/archive documentation process: `references/process.archive.md`

## Quick Routing By Change Type

- Building or changing routes/server functions:
  - `references/organization.routes.md`
  - `references/organization.interfaces.http.md`
  - `references/organization.monorepo.md`
  - `references/organization.featureSlice.md`
  - `references/organization.dataPaths.md`
  - `references/data.access.md`
- Working on auth, membership, or account scope:
  - `references/auth.overview.md`
  - `references/auth.clerk.md`
  - `references/data.multiTenancy.md`
- Updating UI, tokens, or page presentation:
  - `references/design-system.md`
  - `references/design.principles.md`
  - `references/marketing.md`
  - `references/marketing.seo.md`
- Deploying or changing Cloudflare setup:
  - `references/platform.environments.md`
  - `references/platform.dns.md`
- Working on request lifecycle, logging, or runtime config:
  - `references/runtime.logging.md`
  - `references/runtime.config.md`
  - `references/runtime.dependencyInjection.md`
  - `references/runtime.ai.md`
  - `references/runtime.streaming.md`
- Writing or refactoring TypeScript style:
  - `references/codeStyle.typescript.md`
  - `references/codeStyle.designPrinciples.md`
- Adding or updating tests:
  - `references/runtime.testing.md`
  - `references/packages.tanstackStart.md`

## Maintenance Notes

- Keep this index concise and route-oriented.
- Prefer updating existing docs over creating near-duplicate files.
- When adding, renaming, or removing a reference, update this index in the same change.
- Keep long historical notes under `change.*` and read them only when explicitly relevant.
