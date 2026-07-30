# TanStack Query Notes (apps/app)

This note captures the TanStack Query integration pattern we validated while implementing workout generation + status polling in `apps/app`.

## Router-Level Integration Pattern

Use the `browser-old` pattern for TanStack Start + TanStack Router:

- Create a single `QueryClient` inside `getRouter()`.
- Attach it to router context.
- Call `setupRouterSsrQueryIntegration(...)` so SSR/router query behavior is wired correctly.
- In root route, provide that same client via `QueryClientProvider`.

Current implementation:

- `apps/app/src/router.tsx`
  - defines `RouterContext` with `queryClient`
  - creates `QueryClient`
  - sets router `context: { queryClient }`
  - calls `setupRouterSsrQueryIntegration`
- `apps/app/src/routes/__root.tsx`
  - uses `createRootRouteWithContext<RouterContext>()`
  - reads router context via `useRouter()`
  - passes router-owned client into `QueryClientProvider`

## Feature-Level Pattern

Inside components, read the client with:

- `const queryClient = useQueryClient()`

Do not manually reach into router context in feature components when query hooks already provide `useQueryClient`.

## Mutation + Polling Workflow

For generated workout flow (`apps/app/src/components/app/GenerateNewWorkout.tsx`):

- Trigger creation with `useMutation`.
- On mutation success, save `workoutId` in local state.
- Start a status query with `useQuery` and `enabled` guard.
- Set `refetchInterval: 5000` while generation is in progress.
- Stop polling when status returns `complete: true`.
- Invalidate dependent list data with `queryClient.invalidateQueries({ queryKey: ['workouts'] })`.

This gives deterministic refresh behavior without full page reload.

## Query Key Conventions Used

- Workouts list: `['workouts']`
- Generated workout status: `['generated-workout-status', workoutId]`

Keep keys stable and scoped to the domain entity to simplify invalidation.

## Query/Mutation File Organization (from `browser-old`)

`browser-old` uses a feature-slice pattern where query configs and mutation hooks live in the same domain folder as related server functions.

Example (`browser-old/src/lib/workouts`):

- `listWorkouts.ts`, `getWorkout.ts` (server functions)
- `workoutsQuery.ts`, `workoutQuery.ts` (query option builders)
- `useAddWorkoutMutation.ts`, `useUpdateWorkoutMutation.ts` (mutation hooks)

Two important conventions from that structure:

- Keep reusable query configs in `*Query.ts` files with `queryOptions(...)`.
- Keep reusable mutation hooks in `use*Mutation.ts` files and centralize invalidation there.

Applied structure in `apps/app`:

- Server workout functions moved to `apps/app/src/server/workouts/*`.
- Client query/mutation helpers added to `apps/app/src/client/workouts/*`:
  - `workoutsQuery.ts`
  - `generatedWorkoutStatusQuery.ts`
  - `useGenerateWorkoutMutation.ts`

This keeps route/component code small and makes query key reuse + invalidation more consistent.

## Data/Schema Support for Polling

Polling relies on `workouts.complete`:

- Schema field is in `apps/app/src/infra/db/tables/workoutTable.ts`.
- Migration files are in `apps/app/src/infra/db/migrations/`.
- Server status endpoint: `apps/app/src/server/workouts/readGeneratedWorkoutStatus.ts`.

## Practical Rules Learned

- Prefer router-owned `QueryClient` + SSR integration over ad-hoc local clients.
- Prefer `useQueryClient` inside features.
- Prefer query invalidation over `window.location.reload()`.
- Keep polling start/stop state explicit (`enabled`, `refetchInterval`).
- Use narrow status endpoints for polling instead of refetching large datasets.
