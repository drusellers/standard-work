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

## Time and Deterministic Tests

Treat time as a dependency whenever behavior depends on “now,” elapsed time, delays, or timers. For the underlying domain concepts and pitfalls, see [Time: Model the Meaning First](runtime.time.md).

- Inject a clock/time provider or pass an explicit timestamp into pure logic instead of reading the system clock throughout business code.
- Capture “now” once per operation when multiple decisions must use the same instant.
- Use UTC instants for storage and comparisons. Make the time zone explicit for calendar rules; cover daylight-saving transitions when relevant.
- Use a monotonic time source for elapsed durations rather than subtracting wall-clock timestamps, which can jump.
- In tests, freeze time for fixed-instant assertions and advance fake time for expiration, retries, scheduling, and timeout behavior. Avoid real sleeps.
- Test just before, exactly at, and just after important boundaries. Define whether the boundary is inclusive.
- Control both the clock and the timer/scheduler when testing delayed work; changing “now” alone does not necessarily trigger timers. Await asynchronous work before asserting.

### .NET: TimeProvider

- Prefer the built-in `TimeProvider` (.NET 8+) over a custom clock abstraction. Inject it and use `TimeProvider.System` in production.
- Read UTC time with `GetUtcNow()`. For elapsed time, use `GetTimestamp()` and `GetElapsedTime()`.
- Route delays and timers through provider-aware APIs, such as `Task.Delay(delay, timeProvider, cancellationToken)` and `timeProvider.CreateTimer(...)`, instead of bypassing the injected provider.
- In tests, use `FakeTimeProvider` from the `Microsoft.Extensions.TimeProvider.Testing` package (`Microsoft.Extensions.Time.Testing` namespace). Initialize it to a known instant and call `Advance(...)` to move time forward without waiting.
- Give each test its own provider. Do not change the machine clock or rely on global clock overrides.

```csharp
using Microsoft.Extensions.Time.Testing;

public sealed class Expiration(TimeProvider timeProvider)
{
    public bool IsExpired(DateTimeOffset expiresAt) =>
        timeProvider.GetUtcNow() >= expiresAt;
}

// In a test:
var time = new FakeTimeProvider(
    new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
var expiration = new Expiration(time);
var expiresAt = time.GetUtcNow().AddMinutes(5);

Assert.False(expiration.IsExpired(expiresAt));
time.Advance(TimeSpan.FromMinutes(5));
Assert.True(expiration.IsExpired(expiresAt));
```

### TypeScript: Vitest

Use `vi.useFakeTimers()` and `vi.setSystemTime(...)` for code that reads the global clock. Advance scheduled work with `await vi.advanceTimersByTimeAsync(...)` when appropriate, and restore real timers with `vi.useRealTimers()` in cleanup. Prefer an injected clock for business logic when global timer replacement would affect unrelated code.

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
