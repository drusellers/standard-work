# Effection Overview (from sweatpants + hydra)

This document is a practical reference for using Effection in this codebase, based on:

- `https://frontside.com/effection/` package website
- `/Users/drusellers/dev/oss/sweatpants/apps/hydra` tutorial
- `/Users/drusellers/dev/oss/sweatpants` usage patterns

## What Effection is

Effection is structured concurrency for JavaScript/TypeScript.

Core guarantees:

1. Child async work cannot outlive its parent scope.
2. Cleanup runs reliably (`finally`/`ensure`) when scopes halt.
3. Cancellation is explicit and compositional.

In practice, this prevents classic async leaks (orphaned timers, dangling servers, incomplete shutdown).

## Mental model

- **Operation**: lazy async recipe (`function* ...: Operation<T>`).
- **Task**: running child operation (can `yield*` for result or `halt()`).
- **Scope**: lifecycle boundary for tasks/resources.
- **Resource**: long-lived managed service with setup + guaranteed teardown.

Key shift from Promises:

- Promise world: "run as long as needed."
- Effection world: "run only as long as parent still needs it."

## Core primitives and when to use them

- `main(op)`: preferred app entrypoint; handles signals and graceful shutdown.
- `run(op)`: low-level runner; use for tests or narrow control.
- `yield*`: operation composition (Effection equivalent of `await`).
- `spawn(() => op)`: start child task in current scope.
- `all([...ops])`: parallel all; halts siblings on first failure.
- `race([...ops])`: first result/error; halts losers.
- `action((resolve, reject) => cleanup)`: wrap callback APIs; must return cleanup.
- `call(() => promise)`: bridge Promise-producing APIs when explicit cleanup is elsewhere.
- `resource(function* (provide) { ... })`: build long-lived services.
- `provide(value)`: expose resource value while keeping resource alive.
- `ensure(() => cleanup)`: concise cleanup registration.
- `suspend()`: keep task/resource alive until halted.

Also useful (called out in official v4 docs):

- `until(promise)`: convert Promise -> Operation.
- `withResolvers()`: create externally-resolved Operation pair (Effection analogue to `Promise.withResolvers()`).
- `stream(asyncIterable)`: convert `AsyncIterable` -> `Stream`.
- `subscribe(asyncIterator)`: convert `AsyncIterator` -> `Subscription`.
- `once(target, event)`: wait for a single `EventTarget` event.
- `on(target, event)`: stream recurring `EventTarget` events.

## Communication model

### Channels (internal Effection-to-Effection)

- Create with `createChannel<T, TClose>()`.
- Send with `yield* channel.send(value)`.
- Consume with `for (const value of yield* each(channel)) { ...; yield* each.next(); }`.
- Non-buffered: subscribe before producing, or messages can be dropped.

### Signals (callbacks/external -> Effection)

- Create with `createSignal<T, TClose>()`.
- Send with `signal.send(value)` (sync function, no `yield*`).
- Use for DOM handlers, EventEmitter callbacks, timer callbacks, async glue code.
- Consume exactly like channels (`each(...)`).

### Streams (unifying abstraction)

- `Stream<T, TClose> = Operation<Subscription<T, TClose>>`.
- Channels and Signals are both Streams.
- Each `yield* stream` creates a fresh subscription/queue.
- Prefer `Stream` in function signatures when consumer should accept any producer type.

## Context and dependency flow

- Create ambient scoped values with `createContext<T>(name[, default])`.
- Set via `yield* Ctx.set(value)`, read via `yield* Ctx.expect()`/`yield* Ctx.get()`.
- Context is scope-local and inheritable; child scopes can override without mutating parent value.
- Use for shared infra (pools, logger, DB handles, request metadata), not arbitrary app state.

## Scope API integration patterns

Use for integrating Effection with non-generator callback worlds (Express handlers, framework hooks, tests).

- `const scope = yield* useScope()` inside operation/resource.
- In callback/async code: `await scope.run(function* () { ... })`.
- Prefer `scope.run()` over top-level `run()` to preserve parent/child lifecycle and context inheritance.
- `createScope()` for isolated test scopes; always call returned `destroy()` in teardown.
- `useAbortSignal()` for APIs like `fetch` so halts trigger actual abort.
- Scope lifecycle outcomes to keep in mind: return, error, halt (all trigger child teardown).

## Patterns observed in sweatpants/hydra

### 1) Server as resource

- Wrap Express server in `resource`.
- Start with `yield* call(() => new Promise(...listen...))`.
- In `finally`, call `server.close()` and wait for `'close'` with another `call`.

### 2) Daemon watcher

- Spawn watcher task that waits for unexpected server close/error.
- Throw typed error (`ServerDaemonError`) to propagate failure up the tree.

### 3) Pool with Promise API + Effection internals

- Externally expose Promise methods (`getOrCreate`, `shutdown`) for easy `await` in Express.
- Internally bridge back into Effection using captured `scope.run(...)`.
- Use dedup map for concurrent same-key creations.

### 4) Event stream from infra component

- Emit lifecycle events via `createSignal` from any execution context.
- Expose as `Stream` and consume via `each()` in spawned observers.

### 5) Long-lived roots

- Root operation creates resources and observers, then `yield* suspend()`.
- Ctrl+C halts tree, triggering deterministic cleanup for all children/resources.

## Important do/don't guidance

Do:

- Use `spawn` inside operations for concurrency.
- Keep cleanup in `finally`/`ensure` near allocation.
- Use `resource` for anything that must stay alive and be interacted with.
- Use Signals for callback-originated events.
- Call `yield* each.next()` inside `for (const x of yield* each(...))` loops.
- Keep halt paths fast and reliable; avoid expensive work/errors during teardown.

Don't:

- Don't call top-level `run()` from inside an operation when you mean child work (creates orphan scope).
- Don't use Channels as callback sinks when producer cannot `yield*`.
- Don't forget to destroy scopes created via `createScope()`.
- Don't close servers/sockets without awaiting/observing actual close completion.

## Quick selection guide

- Need one async value with callback cleanup -> `action`.
- Need to await Promise API inside operation -> `call`.
- Need parallel children tied to current lifecycle -> `spawn` / `all` / `race`.
- Need long-lived service + cleanup -> `resource` + `provide`.
- Need internal async message passing -> `Channel`.
- Need external callback events -> `Signal`.
- Need ambient dependency/config -> `Context`.
- Need framework/callback bridge -> `useScope` + `scope.run`.

## Canonical capstone stack (hydra)

- `main()` root
- `useServerPool()` resource (dynamic backend tasks)
- `useSwitchboard()` resource (front proxy)
- `spawn(each(pool.events))` observer task
- request handler calls `await pool.getOrCreate(hostname)`
- pool uses `scope.run()` to spawn managed server tasks
- each server built as resource + daemon watcher
- shutdown via parent halt -> full tree cleanup

This is a strong template for production Node services that need dynamic workers, observability streams, and deterministic shutdown.

## Notes from frontside.com (official docs)

Cross-checked against the official Effection v4 site and guides:

- Positioning: "Structured Concurrency and Effects for JavaScript," focused on leak-proof async cleanup.
- Guarantees emphasized in docs: no child outlives parent, every operation exits fully, idiomatic JavaScript control flow.
- API mapping emphasized by Async Rosetta Stone: `await <-> yield*`, `Promise <-> Operation`, `for await <-> for yield* each`.
- Runtime support: Node/browser via npm package `effection`; Deno via `jsr:@effection/effection`.
- Recommended learn sequence in guides: installation -> thinking model -> rosetta -> operations/spawn/resources/collections/events/context/actions -> scope.

Useful reference entrypoints:

- https://frontside.com/effection/
- https://frontside.com/effection/guides/v4/thinking-in-effection
- https://frontside.com/effection/guides/v4/async-rosetta-stone
- https://frontside.com/effection/guides/v4/operations
- https://frontside.com/effection/guides/v4/scope
