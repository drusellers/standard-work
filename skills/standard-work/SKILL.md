---
name: standard-work
description: Dru's standard work for coding and architecture. Use when designing, implementing, refactoring, reviewing, or testing code; choosing project structure; working with TypeScript, data access, auth, runtime behavior, AI, streaming, Cloudflare environments, TanStack, UI, marketing, SEO, or CLI/HTTP interfaces.
---

# Standard Work

This skill provides Dru's reusable standard work for software engineering as lazy-loaded Markdown references.

## Core Rule

Do **not** read every reference file up front. Load only what is relevant to the task.

## Workflow

1. Identify the task area: code style, architecture, runtime, data, auth, UI, AI, testing, platform, package usage, marketing, or interface design.
2. Read `references/index.md` first when routing is unclear.
3. Search narrowly when needed:
   - Use `bash scripts/search "query"` from this skill directory, or
   - Use `rg "query" references/` from this skill directory.
4. Read only the specific reference files needed for the current task.
5. Apply the standards as implementation guidance, review criteria, or design constraints.
6. Prefer the active repository's local instructions when they conflict with these shared standards.

## Common Entry Points

- TypeScript style: `references/codeStyle.typescript.md`
- Design principles and API shape: `references/codeStyle.designPrinciples.md`
- Testing: `references/runtime.testing.md`
- Monorepo organization: `references/organization.monorepo.md`
- Feature slices: `references/organization.featureSlice.md`
- Data access: `references/data.access.md`
- Multi-tenancy: `references/data.multiTenancy.md`
- Auth overview: `references/auth.overview.md`
- Runtime config/logging/DI: `references/runtime.config.md`, `references/runtime.logging.md`, `references/runtime.dependencyInjection.md`
- AI and streaming: `references/runtime.ai.md`, `references/runtime.streaming.md`
- Cloudflare environments/DNS: `references/platform.environments.md`, `references/platform.dns.md`
- TanStack Start/Query: `references/packages.tanstackStart.md`, `references/packages.tanstackQuery.md`
- UI and design system: `references/design-system.md`, `references/design.principles.md`

## Large References

`references/change.ai.md` and `references/change.workoutGeneration.md` are long change/architecture notes. Read them only when the task is specifically about those historical designs or migrations.
