# Runtime Testing

This doc is the starting point for testing conventions in this repo.

We are intentionally beginning with a small, practical baseline and will expand this guidance over time.

## Current Direction

- Use Vitest for tests in app code.
- Keep tests close to the runtime/server code they validate.
- Prefer fast feedback loops locally (`vitest run <file>` while iterating).
- Start with clear unit and integration test boundaries.

## Tooling: Vitest + Vite

Vitest is built on top of Vite. In practice this means:

- Test execution uses Vite's module graph/transforms.
- TypeScript and ESM behavior should closely match app runtime behavior.
- App-level test config can live in `vitest.config.ts` when we need to decouple test execution from app plugins.

Current example:

- `apps/app/vitest.config.ts` uses a Node test environment for server-oriented tests.

## Test Types (Initial)

### Unit tests

Unit tests validate focused logic in isolation.

- Scope: one function/module.
- Inputs/outputs are explicit and deterministic.
- Avoid runtime dependencies unless the dependency is itself under test.

Examples in this repo include conversion/validation utilities (for example duration parsing and formatting).

### Integration tests

Integration tests validate behavior across multiple units and boundaries.

- Scope: a workflow or service path (for example prompt construction + AI response parsing + schema validation).
- May use stubs for external systems while still exercising the internal integration path.
- Favor high-signal assertions that mirror real failure modes.

Current example:

- `apps/app/src/server/ai/workoutGeneration.integration.test.ts`

## Running Tests

From repository root:

```bash
npm run test --workspace @chalkmd/app -- src/server/ai/workoutGeneration.integration.test.ts
```

Run all app tests:

```bash
npm run test --workspace @chalkmd/app
```

## Next Additions (Planned)

We will extend this document with additional test types later, including broader end-to-end/runtime validation patterns where appropriate.

## Open Topic: Mocking and JavaScript Testing Philosophy

We should capture a shared team position on:

- When mocking is appropriate vs when to prefer real collaborators.
- How deep mocks should go in integration tests.
- JavaScript testing style preferences (assertion granularity, failure messaging, test readability).

This section is intentionally a placeholder for your upcoming guidance.
