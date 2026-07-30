# Models Map

This document is the index and shared conventions for domain/data models.

## Shared Conventions

- IDs: all entity IDs are UUIDs.
- Database naming: PostgreSQL columns use `snake_case`.
- Table naming: use **singular** names (e.g., `workout`, not `workouts`).
- Application naming: TypeScript/JavaScript model fields use `camelCase`.
- ORM mapping: Drizzle maps between SQL column names and JS field names.

## Open Decisions Usage

- Every model doc should include an `Open Decisions` section.
- Use it to track unresolved domain constraints, invariants, and schema choices.
- Keep items short and explicit so they can be resolved and removed.
- If there are no current open questions, write `- None currently.`

## Model Primitives

### Duration

- Domain shape: `{ value: number, unit: 'sec' | 'min' | 'hr' }`.
- Allowed units are strict enum values: `sec`, `min`, `hr` (not free-form strings).
- `value` is an integer quantity.
- D1/SQLite storage type: `TEXT` ISO-8601 duration.
- Mapping rule: app/domain uses `Duration`; persistence layer maps to/from ISO-8601 strings.
- Normalization rule: persistence writes durations as canonical seconds strings (`PT{n}S`).
- Non-stringly rule: never persist duration as free-form text; use typed conversion logic in Drizzle.

### TimeUnits

- Enum values: `sec`, `min`, `hr`.

## Standard Audit Fields

Unless a model explicitly says otherwise, include these audit fields:

- `created_at` <-> `createdAt` (default: `now()` & `NOT NULL`)
- `updated_at` <-> `updatedAt` (default: `now()` & `NOT NULL`)
- `deleted_at` <-> `deletedAt` (soft delete) `NULLABLE`

## Standard Indexes
- index on ID for PK 
- index on deleted_at - for active queries

## Model Index

This shared standards package does not maintain per-application model docs.

When a project needs model-specific documentation, keep it in that project's local docs and use this file for shared conventions only. Per-model docs should include:

- Purpose and ownership boundaries.
- Persistence table/collection names.
- ID, audit, and soft-delete behavior.
- Domain invariants.
- Relationships to other models.
- Open decisions.

## Per-Model Template

Use this lightweight template in the consuming project:

```markdown
# ModelName

## Purpose

## Persistence

## Fields

## Relationships

## Invariants

## Open Decisions

- None currently.
```
