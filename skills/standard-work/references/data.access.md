# Data Access Strategy (ChalkMD)

This document defines database and background-job data access choices for a Cloudflare-first architecture.

## Goals

- Keep application data in a durable relational store.
- Keep type-safe data access across apps and workers.
- Support queue-driven background processing with clear ownership and idempotency.
- Preserve strong developer inspection workflows (for example, DataGrip).

## Database

**Cloudflare D1 (SQLite)** is our chosen database for the ChalkMD stack.

D1 provides:

- Native Cloudflare integration with low operational overhead.
- Fast setup for Worker-bound apps via `wrangler.jsonc` bindings.
- SQLite model optimized for our cloud-native architecture.
- Direct integration with Drizzle ORM for type-safe queries.

Considerations:

- SQLite has different SQL behavior than Postgres—some queries may need adjustment.
- Richer reporting may require data export to external analytics tools.
- Use SQLite-compatible patterns for migrations and queries.

Reasoning:

- Keeps the app cloud-native in the Cloudflare runtime and binding model.
- Reduces operational overhead while core product modeling is still evolving.
- Works directly with Drizzle + Worker bindings in `wrangler.jsonc`.

## Data Access Layer Decision

Chosen data access library: **Drizzle**.

Why Drizzle:

- Schema-first model with typed query APIs.
- SQL-like query builder that maps directly to familiar SQL (`select`, `insert`, `update`, `delete`, joins, filters).
- Integrated migration workflow.
- Works for both SQLite (D1) and Postgres paths.

### Query style policy (Drizzle SQL-like)

- Use Drizzle's SQL-like APIs for app and worker data access.
- Prefer `db.select().from(...).where(...)`, `db.insert(...).values(...)`, `db.update(...).set(...).where(...)`, and `db.delete(...).where(...)` over raw driver `.prepare(...).bind(...)` calls.
- Use Drizzle operators (`eq`, `and`, `or`, `inArray`, `desc`, etc.) for filters and sorting.
- Use `sql\`\`` only when needed for atomic expressions or DB functions not covered by first-class helpers.
- Keep query examples and repository code SQL-readable so generated SQL intent is obvious.

Type discipline rules:

- Keep explicit domain contracts at module boundaries.
- Treat boundary data as `unknown` until parsed by schema.
- Use `zod` for boundary validation (HTTP input, queue payloads, webhook payloads, env config, and third-party API responses).
- Prefer parsing at boundaries and pass inferred types inward.
- Avoid type assertions/casts for runtime data narrowing in normal paths.
- Avoid spreading inferred ORM-only types across app/service layers.

## Current App Conventions (D1 + Drizzle)

### Runtime and bindings

- Primary app DB is D1 via `DB` binding in `apps/app/wrangler.jsonc`.
- Worker env validation uses app-local `WorkerEnv` Zod schema.
- Drizzle D1 client is created from the validated `DB` binding.

### Schema organization

- Use one file per table under `apps/app/src/infra/db/tables/`.
- Keep shared custom Drizzle types under `apps/app/src/infra/db/tables/customTypes/`.
- Keep `apps/app/src/infra/db/schema.ts` as a thin re-export layer.

### Naming and shape

- SQL column names use `snake_case`.
- TS/JS model fields use `camelCase`.
- Tenant-owned tables include `account_id`.
- Standard audit columns: `created_at`, `updated_at`, `deleted_at`.

### Migrations

- Generate migrations with Drizzle (`drizzle-kit generate`).
- Apply D1 migrations with Wrangler (`wrangler d1 migrations apply ...`).
- Keep migration files in `apps/app/src/infra/db/migrations/`.
- Keep migration files DB-native SQL; do not rewrite migrations into runtime query-builder code.

### Duration primitive

- Domain primitive name: `Duration`.
- Domain shape: `{ value: number, unit: 'sec' | 'min' | 'hr' }`.
- Persist in SQLite as ISO-8601 `TEXT` durations.
- Normalize writes to canonical seconds form: `PT{n}S`.
- Enforce non-stringly behavior with typed conversion in Drizzle custom types.

## Cloudflare Queue Access Pattern

Use Cloudflare Queue as transport, with D1 as source of truth.

### Ownership

- `apps/app`:
  - Write business state to DB.
  - Insert outbox job rows in the same transaction.
- `apps/jobs-worker`:
  - Scheduled dispatcher publishes pending outbox rows to Queue.
  - Queue consumer executes jobs and writes run status/results to DB.
- `packages/jobs`:
  - Shared job names, payload schemas, and idempotency helpers.

### Worker bindings

- Producer binding (send): queue binding in `apps/app/wrangler.jsonc` if publishing directly.
- Consumer binding: queue consumer config in `apps/jobs-worker/wrangler.jsonc`.
- Scheduled trigger: cron trigger in `apps/jobs-worker/wrangler.jsonc` for outbox dispatch.

### Message shape

- Include `jobId`, `jobType`, `attempt`, `createdAt`, and minimal `payload`.
- Keep payloads small and fetch larger context from DB.
- Validate every message with shared `zod` schema before processing.

### Reliability rules

- Idempotency key: unique `jobId` enforced in DB.
- At-least-once processing: consumer must be safe on retries.
- Retry/backoff + dead-letter queue configured at Queue level.
- Persist job lifecycle (`queued`, `processing`, `succeeded`, `failed`) in DB for auditability.

## Suggested Package Layout

- `packages/data-access`:
  - Drizzle schema definitions.
  - DB client setup.
  - Repository/query modules.
- `packages/jobs`:
  - Job contracts (`jobType`, payload schemas, event versions).
  - Utilities for enqueue metadata and idempotency keys.

## Decision Snapshot

- Database: **Cloudflare D1 (SQLite)**.
- Data access: **Drizzle**.
- Background transport: **Cloudflare Queues**.
- Background processor: **`apps/jobs-worker`**.
- Source of truth for job state: **D1**.

## D1 Limitations

### Transactions

D1 does not support Drizzle ORM's `db.transaction()` method. When using transactions,
D1 issues SQL `BEGIN TRANSACTION` statements which are not supported in local development
mode (wrangler dev) and may behave unexpectedly in production.

**Error you'll see:**
```
D1_ERROR: To execute a transaction, please use the state.storage.transaction() or
state.storage.transactionSync() APIs instead of the SQL BEGIN TRANSACTION or SAVEPOINT statements.
```

**Workaround**: Perform database operations sequentially without explicit transactions:

```typescript
// Instead of:
return this.db.transaction(async (tx) => {
  const result1 = await db.insert(table1).values(data1);
  const result2 = await db.update(table2).set(data2).where(...);
  return result1;
});

// Do this:
const result1 = await db.insert(table1).values(data1);
const result2 = await db.update(table2).set(data2).where(...);
return result1;
```

For operations requiring atomicity, consider:
- Using D1's batch API for multiple statements
- Implementing compensating transactions for rollback scenarios
- Using Cloudflare Durable Objects with `state.storage.transaction()` for true atomic operations
