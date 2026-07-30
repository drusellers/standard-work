# Feature Slice Organization Notes

This document summarizes the feature-slice patterns observed in `browser-old` and how we should apply them in this repo.

## What `browser-old` does well

`browser-old` groups domain logic by feature (for example `workouts`, `templates`, `movements`) instead of by technical layer only.

Observed in:

- `browser-old/src/lib/workouts/*`
- `browser-old/src/lib/templates/*`
- `browser-old/src/lib/movements/*`

Each feature folder typically includes:

- Server functions (`listWorkouts.ts`, `getWorkout.ts`, `addWorkout.ts`, `updateWorkout.ts`)
- Query option builders (`workoutsQuery.ts`, `workoutQuery.ts`)
- Mutation hooks (`useAddWorkoutMutation.ts`, `useUpdateWorkoutMutation.ts`)
- Feature types (`types.ts`)

Routes stay thin and import feature helpers directly:

- Loaders prefetch with `queryClient.ensureQueryData(queryOptions)`
- Components consume `useSuspenseQuery(queryOptions)`
- Mutations invalidate or update cache in one place

## Principles to keep

- Organize by domain first (workouts/templates/etc).
- Keep query keys and query options reusable and centralized.
- Keep mutation cache behavior close to the mutation hook.
- Keep routes/components focused on UI + orchestration.
- Prefer explicit feature types at boundaries.

This doc explains how to group code by feature. For guidance on how data should move through layers inside a feature, see `references/organization.dataPaths.md`.

## Applied in current repo (`apps/app`)

For workouts, we now separate server modules and client query/mutation modules by feature:

- Server domain slice: `apps/app/src/server/workouts/*`
  - `createWorkout.ts`
  - `listWorkouts.ts`
  - `generateWorkout.ts`
  - `readGeneratedWorkoutStatus.ts`
- Client domain slice: `apps/app/src/client/workouts/*`
  - `workoutsQuery.ts`
  - `generatedWorkoutStatusQuery.ts`
  - `useGenerateWorkoutMutation.ts`

## Recommended folder shape going forward

Use this structure for new features in `apps/app`:

```text
apps/app/src/
  context/
    createAppContext.ts
    createRequestContext.ts
  infra/
    db/
    ai/
    logging/
    auth/
  server/
    <feature>/
      <serverFn>.ts
  domain/
    <feature>/
      <useCase>.ts
      <feature>Repository.ts
      types.ts
  client/
    <feature>/
      <entity>Query.ts
      <entities>Query.ts
      use<Verb><Entity>Mutation.ts
```

The exact filenames can vary, but the intent should stay consistent:

- `src/server/<feature>/` holds input boundaries such as TanStack server functions.
- `src/context/*` holds request/app context composition used by server boundaries.
- `src/domain/<feature>/<useCase>.ts` holds the messy middle: orchestration, business actions, and domain decisions.
- `src/domain/<feature>/<feature>Repository.ts` holds persistence-facing query intent when repository behavior is feature-owned.
- `src/infra/*` holds shared runtime adapters for DB/AI/logging/auth.
- Query builders and mutation hooks stay in `src/client/<feature>/`.

Example for a future `templates` feature:

```text
apps/app/src/
  server/
    templates/
      listTemplates.ts
      getTemplate.ts
      updateTemplate.ts
  domain/
    templates/
      updateTemplate.ts
      templateRepository.ts
      types.ts
  client/
    templates/
      templatesQuery.ts
      templateQuery.ts
      useUpdateTemplateMutation.ts
```

## Organizing inside a feature slice

Feature slices work best when they do more than collect files with similar names. They should also make the path from input to data obvious.

- Boundary code belongs near `src/server/<feature>/`.
- Persistence code belongs in repositories.
- The code in between should be organized as explicit business logic, not left as a grab bag.

Within a feature, the messy middle usually falls into a few buckets:

- `use cases` or `services`: business actions and orchestration.
- `policies`: pure business rules and invariants.
- `mappers` or `translators`: shape conversion between layers.
- `coordinators`: larger multi-step workflows when needed.

That means a feature slice is not only a folder boundary. It is also a data path boundary.

- Requests enter through server functions.
- Business behavior runs through use-case or service modules.
- Persistence goes through repositories.

This makes it easier for people and agents to place new code by asking a simple question: is this module translating input, deciding behavior, or touching storage?

## Practical rules

- Use `queryOptions(...)` builders in feature files; do not inline query keys in many routes.
- Use `useQueryClient()` in feature hooks/components for invalidation and optimistic updates.
- Keep query keys stable (`['workouts']`, `['workouts', workoutId]`, etc.).
- Prefer small status queries for polling flows over refetching large lists.
- When adding server functions, place them under `src/server/<feature>/` first.
- When adding business logic between server functions and persistence, create an explicit use-case/service module instead of embedding that logic at either boundary.
- When adding direct data access for a feature, keep it in a repository so the path from action to storage stays obvious.
