# Data Paths

This document defines how runtime inputs are allowed to reach persistent systems such as the database, queue-backed job state, or search indexes.

## Core Idea

Keep the number of paths from an external input to a data system intentionally small.

- HTTP requests should not fan out into many ad hoc database access patterns.
- CLI entrypoints should not bypass the same domain rules the app uses.
- Data access should move through a small set of explicit layers so behavior is easier to understand, test, and change.

We build layers of indirection on purpose. Each layer narrows the problem, tightens types, and limits where certain decisions can be made.

## Standard Path

The default data path is:

```text
framework input -> controller/server function -> service -> repository -> database/search system
```

Examples:

- HTTP request -> TanStack server function -> feature service -> repository -> D1/Postgres.
- Queue message -> worker handler -> job service -> repository -> database.
- CLI command -> command handler -> service -> repository -> database.

## Why This Matters

- Fewer paths means fewer places to inspect when behavior changes.
- Controllers translate framework-shaped input into application-shaped input.
- Services hold orchestration and business workflow decisions.
- Repositories isolate persistence details, query shape, and storage-specific concerns.
- Strong boundaries make refactors safer because each layer has a smaller surface area.

This is mostly about reasoning, not ceremony. The goal is not to add abstractions everywhere. The goal is to make data access predictable.

## Layer Responsibilities

### Controllers / server functions

- Accept framework-specific input such as HTTP request data, route params, auth context, queue payloads, or CLI args.
- Treat all framework/user-controlled input as `unknown` at the boundary.
- Validate and normalize boundary input.
- Narrow to application-facing types only through schema validation (for example Zod).
- Do not use type assertions (`as`) to skip boundary validation.
- Produce tighter application-facing types.
- Delegate business work instead of embedding persistence logic.

### Services

- Coordinate a use case or workflow.
- Compose multiple repositories or downstream collaborators.
- Enforce business rules that are broader than a single query.
- Define the main application-level path for a feature.

### Repositories

- Own reads and writes against a persistence system.
- Encapsulate SQL, ORM usage, index access, and storage-specific mapping.
- Return domain-shaped results instead of leaking storage details upward.
- Avoid taking raw framework objects as input.

## Organizing The Messy Middle

The boundaries are usually easy to identify.

- Controllers are the input boundary.
- Repositories are the persistence boundary.
- The harder question is how to organize the code between them.

Use data paths to make that middle explicit.

- Boundary code translates.
- Middle code decides and orchestrates.
- Persistence code stores and retrieves.

This gives people and agents a placement rule. If a module is not about accepting framework input and not about talking to storage, it should usually live in the middle as application logic.

### What belongs in the middle

The middle is where business behavior should live. In practice, it usually falls into a few categories.

### Use cases / services

- Represent a business action or workflow.
- Decide what happens and in what order.
- Call one or more repositories or downstream collaborators.
- Keep controllers thin by pulling orchestration out of the boundary.

Examples:

- `createWorkout`
- `generateWorkout`
- `archiveTemplate`

### Policies / domain rules

- Represent business decisions that should survive framework or storage changes.
- Stay as pure and dependency-light as possible.
- Capture invariants, permissions, eligibility rules, and branching logic.

Examples:

- `canGenerateWorkout`
- `canArchiveTemplate`
- `selectPlanForUser`

### Translators / mappers

- Convert one application shape into another.
- Normalize data between boundary, domain, and persistence layers.
- Prevent request-shaped or row-shaped objects from leaking too far.

Examples:

- request input -> service input
- DB row -> domain model
- job payload -> internal command

### Coordinators

- Handle longer multi-step flows when a single service would otherwise become too large.
- Useful for imports, background jobs, indexing flows, and cross-feature workflows.
- Still sit above repositories and below controllers.

Use this only when the workflow is meaningfully larger than a normal service, not as a default extra layer.

## Placement Heuristics

When deciding where code belongs, ask what the module knows about.

- If it knows about HTTP requests, route params, auth headers, framework context, or CLI args, it belongs at the controller boundary.
- If it knows about SQL, Drizzle, table layout, D1/Postgres bindings, or search APIs, it belongs at the repository boundary.
- If it knows sequencing, branching, rules, orchestration, retries, or which repositories to call, it belongs in the middle.

A useful smell:

- If a module imports both controller-shaped input and ORM-shaped data access, it is probably doing too much.
- Move the decision-making into a service or use-case module and keep the boundaries narrower.

## A Simple Checklist

When adding or moving code, classify it before naming it.

- Does it parse, validate, authenticate, or shape input/output? -> controller.
- Does it represent a business action? -> service or use case.
- Does it enforce a business rule that should outlive transport and storage details? -> policy.
- Does it convert between shapes? -> translator or mapper.
- Does it only read or write persistent data? -> repository.

The purpose of this structure is not to create ceremony. It is to give the business logic between the boundaries an obvious home.

## Boundary Rules

- Routes, loaders, actions, and worker handlers should not issue ad hoc database queries directly when the code represents domain behavior.
- Feature code should prefer one obvious service path over many alternative call chains.
- Repositories are the default place for direct DB or search access.
- If multiple entrypoints need the same behavior, share a service instead of duplicating repository orchestration.
- Boundary parsing should happen once at ingress; downstream modules should consume validated, typed data only.
- If validation or type normalization happens at the boundary once, downstream code can stay smaller and stricter.

## Monorepo and Feature-Slice Fit

This concept complements the repo's existing organization guidance.

- `references/organization.featureSlice.md` explains grouping by domain.
- This document explains how work should move through that domain slice.
- In practice, each feature slice should expose a small set of service entrypoints and keep persistence in repositories below them.

Typical shape inside an app:

```text
apps/app/src/
  context/
    createAppContext.ts
    createRequestContext.ts
  server/
    workouts/
      createWorkout.ts      # controller / server function
  domain/
    workouts/
      createWorkoutService.ts
  infra/
    db/
      workoutRepository.ts
  client/
    workouts/
      workoutsQuery.ts
      useCreateWorkoutMutation.ts
```

Exact filenames can vary, but the path should stay clear: input boundary first, orchestration next, persistence last.

## When To Bend The Rule

Some code paths do not need every layer.

- A simple read may go from controller to repository directly if there is no orchestration to preserve.
- Low-level infrastructure code may talk to storage directly when it is itself the repository layer.
- Scripts for one-off maintenance can be simpler, but should still avoid inventing a second business path if the app already has one.

Use the simplest path that still preserves one clear place for business rules and one clear place for persistence behavior.

## Decision Heuristic

When adding a new feature, ask:

- What is the approved path from this input to data?
- Where does boundary validation happen?
- Where does orchestration live?
- Where is the only place this query or write logic should exist?

If those answers are not obvious, the data path is probably too loose.
