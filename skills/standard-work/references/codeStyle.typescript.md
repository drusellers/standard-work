# TypeScript Code Style

This document defines TypeScript style conventions for readability and maintainability.

## Core Rule

- Do not use ternary expressions.
- Prefer explicit `if` / `else` branches, even for short conditions.
- Lint enforcement: `biome` rule `lint/nursery/noTernary` is enabled.
- Do not use `Pick` or `Omit` to define application types.

## Why

- `if` / `else` reads better in code review and logs intent more clearly.
- Explicit branches make follow-up edits safer when logic grows.
- It keeps conditionals consistent across the codebase.
- `Pick` and `Omit` force readers to mentally reconstruct a new shape from another type.
- When a type has its own meaning, define it directly so the reader can understand it without translating from a source type.
- Our type system should reduce cognitive load, not depend on remembering and reshaping existing types in your head.

## Preferred Pattern

Use explicit branch logic:

```ts
let label = ""

if (isActive) {
	label = "active"
} else {
	label = "inactive"
}
```

Return branches directly when appropriate:

```ts
if (!run) {
	return null
}

return run.id
```

## Related Guidance

- Active repository TypeScript direction and constraints: local `AGENTS.md`, when present
- Runtime validation and schema-first guidance: `references/runtime.ai.md`, `references/runtime.config.md`

## Notes

- We can add before/after examples and exception handling guidance here over time.
