# Multi-Tenancy Strategy (ChalkMD)

This document defines how tenancy should work across `apps/app`, `apps/jobs-worker`, and shared packages.

Status: proposed baseline for v1.

## Goals

- Make tenant boundaries explicit in both code and schema.
- Prevent cross-tenant data access by default.
- Keep query patterns ergonomic for Drizzle + D1.
- Support background jobs safely in a multi-tenant model.
- Keep room for future features (team sharing, custom domains) without redesign.

## Tenancy Model

**User tenancy** — a tenant is a `user`.

- Each user is isolated by their Clerk user ID.
- Most business records are owned by exactly one user.
- Tenant scope is represented by `user_id` on tenant-owned tables.

For future vNext features like team collaboration or shared plans, we will introduce an `account` model as an optional layer above users (not a replacement). For v1, data ownership stays at the user level.

## Canonical Identity Key

Use the stable external ID from Clerk directly as the canonical reference.

- `users.clerk_user_id` (unique)

Keep an internal UUID primary key for relational joins and storage ergonomics.

## Core Tables (Minimum)

### `user`

- `id` (uuid pk)
- `clerk_user_id` (text unique not null)
- `primary_email` (text nullable)
- `created_at`, `updated_at`

### `user_avatar`

Purpose: track avatar lifecycle from external/source URL to internal R2 storage, with provenance and controls.

- `id` (uuid pk)
- `user_id` (uuid fk -> user.id)
- `source_url` (text not null)
- `source_kind` (text/enum, e.g. `clerk|google|github|upload|unknown`)
- `r2_bucket` (text nullable)
- `r2_key` (text nullable)
- `r2_url` (text nullable, if exposing a stable public/served URL)
- `status` (text/enum, e.g. `pending|fetched|processed|ready|failed`)
- `mime_type` (text nullable)
- `byte_size` (integer nullable)
- `width` (integer nullable)
- `height` (integer nullable)
- `checksum_sha256` (text nullable)
- `etag` (text nullable)
- `is_current` (boolean not null default false)
- `failure_reason` (text nullable)
- `created_at`, `updated_at`
- `fetched_at` (timestamptz nullable)
- `processed_at` (timestamptz nullable)

Constraints/indexes:

- Exactly one current avatar per user via partial unique index:
  - unique `(user_id)` where `is_current = true`
- Helpful lookup indexes:
  - `(user_id, created_at desc)`
  - `(status, created_at)`
  - unique `(r2_bucket, r2_key)` when both are non-null

Notes:

- This table keeps historical avatar versions for rollback/audit.
- If preferred, `user` may also keep a nullable `current_avatar_id` pointer for fast reads; `is_current` still remains the source of truth.



### Tenant-owned domain tables (pattern)

Every tenant-owned table should include:

- `user_id` (uuid not null fk -> user.id)
- `id` (tenant-local record id, usually uuid)
- `created_at`, `updated_at`

Index pattern:

- Primary access index: `(user_id, <common_filter>, id)`

## Data Ownership Rules

Default rule: if data is business/domain data, it is tenant-owned.

Usually global (not tenant-owned):

- `user`
- `user_avatar`
- feature flags/config intentionally global
- migration metadata/internal infrastructure tables

Tenant-owned by default:

- training blocks, workouts, workout logs
- audit events tied to user actions
- outbox/jobs that operate on user data

## Query Discipline (Application Layer)

Hard rule: all tenant-owned queries include `user_id` filter.

- Never query tenant-owned rows by `id` alone.
- Prefer repository APIs that require `userId` as a first argument.
- For upserts, include tenant key in conflict target where relevant.

Good API examples:

- `getWorkoutById(userId, workoutId)`
- `listTrainingBlocks(userId, filters)`

Avoid:

- `getWorkoutById(workoutId)`

## Postgres Enforcement (Recommended)

Use both application filters and database-level guardrails.

### Option A (v1): app-layer enforcement only

- Faster initial implementation.
- Requires strict repository discipline and code review.

### Option B (preferred soon after v1): Row Level Security

- Enable RLS on tenant-owned tables.
- Set a request-scoped DB setting for tenant context, such as:
  - `set_config('app.current_user_id', '<uuid>', true)`
- Policies enforce `user_id = current_setting('app.current_user_id')::uuid`.

Recommendation:

- Start with app-layer strictness immediately.
- Add RLS once core table set stabilizes.

## Background Jobs in Multi-Tenant Context

Outbox and queue payloads must carry tenant identity.

Required fields in job envelope:

- `jobId`
- `jobType`
- `userId`
- `attempt`
- `createdAt`
- `payload` (minimal)

Rules:

- `userId` is mandatory for user-affecting jobs.
- Consumer re-validates tenant scope before mutating data.
- Idempotency should generally be scoped as `(user_id, job_id)` or globally unique `job_id` with user recorded.

## RBAC Boundary (vNext)

Tenancy and authorization are related but separate concerns.

- Tenancy answers: "which user owns this row?"
- RBAC answers: "what permissions does this user have?"

For v1, permissions are implicit (users can only access their own data). Future vNext features may add roles; evaluate permissions in app/service layer.

## URL and Context Model

Decision for v1: do not put user identity in customer-facing URLs.

- Use clean routes such as `/training`, `/workouts`, `/settings`.
- Resolve user from authenticated session context.
- Keep all server-side authorization scoped by `user_id`.

Regardless of route strategy, server handlers should resolve:

1. authenticated user
2. scoped data access

Deep-link note:

- Internal/admin tooling may still use explicit user-scoped links when operationally useful.
- These links are optional and not required for primary end-user navigation.

### Reserved vNext concept: accounts

- An `account` model is planned as an optional layer for team/organization features.
- For v1, do not add `account_id` to core domain tables.
- When introduced, account membership will be additive—users still own their data, but can share or collaborate within an account context.

## Migration Plan (If Starting Simple)

If any existing tables lack tenant isolation, move in phases:

1. Add nullable `user_id` to tenant-owned tables.
2. Backfill user ownership.
3. Make `user_id` non-null.
4. Add composite indexes and uniqueness scoped by user.
5. Update repositories to require tenant scope.
6. Add RLS policies (optional but recommended).

## Testing Requirements

Add explicit multi-tenant test cases:

- cannot read another user's rows
- cannot update/delete another user's rows
- list endpoints return only authenticated user's rows
- background job for user A cannot mutate user B data

Additional onboarding tests:

- new signup creates user record
- authenticated user can access their own data

## Decision Snapshot

- Tenancy unit: **user**.
- Auth provider integration: **Clerk user ID**.
- Tenant key on domain data: **`user_id`**.
- Enforcement: **app-layer now, RLS soon after v1**.
- Jobs: **tenant-aware envelopes with required `userId`**.
- Reserved term: **account** for future team/organization features (vNext).
