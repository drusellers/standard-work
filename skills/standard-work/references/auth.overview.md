# Authentication Notes (Clerk)

This document captures the v1 authn/authz direction for ChalkMD.

## Current Direction

- Provider: **Clerk**
- Primary app auth surface: `apps/app`
- Tenancy unit: **account** (not workspace)
- Clerk Organizations map to internal `accounts`
- New signup creates a default account
- Users may join multiple accounts over time

Terminology note:

- `workspace` is reserved for a future subdivision within an account (vNext)

## Routing and Session Context

Decision for v1: do not include account identity in customer-facing URLs.

- Use clean routes (`/patients`, `/calendar`, `/settings`)
- Resolve active account from authenticated session context
- Support account switching via app UI (account switcher)
- Keep server-side authorization scoped by membership + `account_id`

Request handlers should always resolve, in order:

1. authenticated user
2. active account
3. membership/role
4. scoped data access

## Postgres Mapping (`auth` schema)

Auth/tenancy-adjacent tables live in schema `auth` for v1:

- `auth.users`
  - canonical external key: `clerk_user_id` (unique)
- `auth.accounts`
  - canonical external key: `clerk_org_id` (unique)
- `auth.account_memberships`
  - join table between users and accounts
  - unique constraint: `(account_id, user_id)`
- `auth.user_avatars`
  - user avatar lifecycle from source URL to R2 target
  - history-friendly with a single current avatar per user via partial unique index

## Synchronization Model (Clerk -> Postgres)

Recommended sync path:

- Upsert `auth.users` from Clerk user identity events/session bootstrap
- Upsert `auth.accounts` from Clerk organization data
- Upsert `auth.account_memberships` from org membership state
- Ensure default account + owner membership exists at initial signup

Implementation note:

- Webhooks are preferred for consistency; session-time backfill/reconciliation is acceptable as safety net.

## Authorization Boundary

Keep concerns separate:

- Authentication: "who is the user?" (Clerk)
- Tenancy: "which account is active?" (`account_id`)
- Authorization: "what can they do in that account?" (membership role + policy)

Tenant-owned data access rules:

- Every tenant-owned query must include `account_id`
- Do not query tenant-owned rows by record `id` alone

## Invite Strategy (Future)

Planned phased approach:

- v1: Clerk-native organization invites + membership sync into `auth.account_memberships`
- vNext (if needed): add internal `auth.account_invites` for richer lifecycle controls and audit

## Multi-Tenant Jobs Note

When auth context crosses async boundaries, job envelopes must include account identity.

- Required tenant field: `accountId`
- Consumers must re-check tenant scope before mutation

## Open Follow-Ups

- Define exact role set for v1 (`owner/admin/member` vs expanded roles)
- Decide timing for RLS on tenant-owned tables (app-layer first vs immediate RLS)
- Define auth webhook processing guarantees (retries, idempotency keys, dead-letter path)

See also:

- `references/data.multiTenancy.md`
