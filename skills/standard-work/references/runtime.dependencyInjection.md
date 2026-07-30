# Runtime Dependency Injection

This document defines how we do dependency injection (DI) with a manually constructed application context in this repo.

## Direction

- Use manual DI with explicit context objects, not container frameworks.
- Construct dependencies at composition roots (framework/runtime edges).
- Pass scoped context into use-cases explicitly.
- Keep route handlers and CLI command wiring thin.
- Prefer type-safe dependency contracts (interfaces/type aliases) over ad-hoc globals.

## Why Manual DI

- Makes dependency graphs visible and testable.
- Keeps runtime-specific code (Cloudflare Worker bindings, `process.env`, stdio) at the edge.
- Allows the same domain use-case to run in multiple adapters (TanStack Start and Commander CLI).
- Avoids hidden coupling through module-level singletons.

## Core Model

Use two context layers:

1. `AppContext`: long-lived services/factories for an app process/runtime.
2. Execution-scoped context:
   - `RequestContext` for TanStack Start server execution.
   - `CommandContext` for Commander command execution.

`AppContext` includes factories and stable services. Scoped contexts add metadata and per-execution values.

## TanStack Start Pattern

### Composition Root

- Build `AppContext` at the TanStack Start runtime boundary from validated Worker env.
- Validate env with the app-local `WorkerEnv` Zod schema once.
- Expose factories (for DB/AI/logging) rather than creating every dependency eagerly.

### Request Scope

- Derive `RequestContext` per request/server function.
- Add request metadata (`requestId`, `accountId`, request-scoped logger).
- Pass `RequestContext` into server use-cases.

### Server Function Rule

- Server function file responsibilities:
  - Parse input with `.inputValidator(...)`.
  - Build/read context.
  - Invoke a use-case.
- Do not import runtime bindings (`cloudflare:workers`) in domain/use-case modules.

Example shape:

```ts
type AppContext = {
  config: WorkerEnv;
  readDb: () => Promise<AppDatabase>;
  readAiRunner: () => Promise<WorkoutAiRunner>;
  makeLogger: (meta?: Record<string, string>) => Logger;
  now: () => Date;
  randomId: () => string;
};

type RequestContext = AppContext & {
  requestId: string;
  accountId: string;
  logger: Logger;
};
```

## Commander CLI Pattern

### Composition Root

- Build one `CliAppContext` at CLI process start.
- Validate CLI env once with a CLI-local Zod schema.
- Configure process-level adapters (`stdout`, `stderr`, `fetch`, AI runner factories).

### Command Scope

- For each command action, derive `CommandContext`.
- Include command metadata (`commandName`, `cwd`, parsed options, cancellation signal).
- Call shared use-cases with `CommandContext` or a narrowed dependency contract.

Example shape:

```ts
type CliAppContext = {
  config: CliEnv;
  stdout: NodeJS.WriteStream;
  stderr: NodeJS.WriteStream;
  readAiRunner: () => Promise<WorkoutAiRunner>;
  now: () => Date;
};

type CommandContext = CliAppContext & {
  commandName: string;
  cwd: string;
  signal: AbortSignal;
};
```

## Shared Use-Case Contract

When a use-case should run in both app and CLI, define a minimal dependency contract for that use-case:

```ts
type GenerateWorkoutDeps = {
  readAiRunner: () => Promise<WorkoutAiRunner>;
  now: () => Date;
};
```

Both `RequestContext` and `CommandContext` can satisfy this contract without framework-specific types leaking into domain logic.

## File Organization

Recommended locations in each app:

- `src/server/*`: adapter/wiring only (TanStack server functions, route handlers, middleware).
- `src/context/createAppContext.ts`: builds app-level context from runtime env.
- `src/context/createRequestContext.ts`: derives request-scoped context.
- `src/domain/*`: business use-cases and domain policies.
- `src/infra/*`: runtime adapters (DB, AI, logging, auth helpers).
- `src/cli/context/createCliAppContext.ts`: builds CLI app context.
- `src/cli/context/createCommandContext.ts`: derives command-scoped context.
- `src/cli/commands/*`: adapter/wiring only.

For app server requests, prefer this dependency direction:

```text
src/server -> src/context -> src/domain -> src/infra
```

## Testing Guidance

- Unit tests: pass fake dependency objects directly (no framework runtime required).
- Integration tests: instantiate real context builders with test env/config.
- Prefer deterministic injected dependencies (`now`, `randomId`) in tests.

## Anti-Patterns

- Importing runtime bindings deep in domain modules.
- Reading `process.env` or Worker `env` inside use-case code.
- Hidden module-level singletons for DB/client/logger.
- Passing very broad context when a narrow dependency contract is enough.

## Migration Notes

- Start by extracting context builders around existing helpers (for example DB client creation).
- Keep old call sites working by adding thin adapter functions during migration.
- Move one feature at a time to explicit dependency contracts.

See also:

- `references/codeStyle.designPrinciples.md#compose-dependencies-through-factories-and-injection`
- `references/runtime.config.md`
- `references/packages.tanstackStart.md`
- `references/runtime.logging.md`
