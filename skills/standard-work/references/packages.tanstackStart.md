# TanStack Start Notes

This note captures the shared patterns we use for TanStack Start server functions and middleware across apps.

## Input Validation Rule

When a server function accepts client-provided input (`{ data }` in the handler), always validate with a Zod schema through `.inputValidator(...)`.

- Define a schema next to the server function.
- Parse unknown input with the schema.
- Use schema transforms and constraints (`trim`, `min`, etc.) instead of ad-hoc normalization helpers.

Preferred pattern:

```ts
const CreateThingInput = z.object({
	name: z.string().trim().min(1, "Name is required"),
});

export const createThing = createServerFn({ method: "POST" })
	.inputValidator((input: unknown) => CreateThingInput.parse(input))
	.handler(async ({ data }) => {
		// data is schema-validated
	});
```

## Why

- Keeps validation declarative and co-located with the server boundary.
- Gives consistent, typed parsing behavior across all server functions.
- Reduces drift between custom validators and route/server contracts.

## Scope

- Apply this pattern for both `POST` and `GET` server functions when they accept input.
- If a server function does not accept input, `.inputValidator(...)` is not required.

## Server Route Validation

- `inputValidator(...)` is a `createServerFn` and function-middleware feature, not a server route handler feature.
- For `createFileRoute(...).server.handlers`, validate request input at the route boundary with `safeParse` (or equivalent) and return `400` for invalid client payloads.
- Prefer shared helpers from `@/infra/http` for consistent request handling and error responses.

### HTTP Request Helpers

Use the shared `readJsonInput` helper to parse JSON and validate with Zod in one call:

```ts
import { readJsonInput, jsonResponse, jsonErrorMiddleware } from "@/infra/http";
import { GenerateWorkoutAIInput } from "@/domain/workouts/ai";

export const Route = createFileRoute("/_/cli/workout-generate-ai")({
	server: {
		middleware: [cliAuthMiddleware, jsonErrorMiddleware],
		handlers: {
			POST: async ({ request }) => {
				const parsedInput = await readJsonInput(
					request,
					GenerateWorkoutAIInput,
					{ invalidInputMessage: "Invalid workout input" },
				);

				const result = await generateAndPersistWorkout(parsedInput, requestContext);
				return jsonResponse(result, 200);
			},
		},
	},
});
```

The helper:
- Parses JSON body (throws `InvalidJsonBodyError` on parse failure)
- Validates against the provided Zod schema (throws `InputValidationError` on validation failure)
- Returns typed data on success

### Error Middleware

Use `jsonErrorMiddleware` to translate typed exceptions into consistent HTTP responses:

| Error Type | HTTP Status | Response Body |
|------------|-------------|---------------|
| `InvalidJsonBodyError` | 400 | `{ error: "Invalid JSON request body" }` |
| `InputValidationError` | 400 | `{ error: "...", details: [...] }` |
| `ZodError` (uncaught) | 502 | `{ error: "...", details: [...] }` |
| `Error` | 500 | `{ error: "..." }` |
| unknown | 500 | `{ error: "Unknown server error" }` |

### Key Principles

- Keep input parsing and domain execution in separate steps so we do not accidentally label domain/output validation failures as input errors.
- Avoid re-parsing the same input schema in deeper layers after the route or server function boundary has already validated it.
- Throw typed errors from helpers; let middleware handle the HTTP response mapping.
- Keep route handlers focused on business logic, not error response formatting.

## Middleware Direction

Use middleware for reusable cross-cutting concerns at server boundaries (auth, request-scoped context, logging, tracing, and shared error shaping).

### Placement and Ownership

- Put reusable middleware in domain-appropriate infra folders (for example `src/infra/auth/*Middleware.ts`).
- Keep route files focused on request-specific parsing and domain orchestration.
- Export middleware from local package barrels (for example `src/infra/auth/index.ts`) so routes and server functions compose from one entry point.

### Request Middleware (Server Routes)

- Use request middleware (`createMiddleware().server(...)`) for TanStack file route server handlers.
- Attach middleware at `server.middleware` to apply to all route methods, or use per-method middleware when behavior differs by method.
- For auth middleware, return a `Response` directly when access should be denied instead of duplicating `try/catch` checks in every handler.

### Function Middleware (`createServerFn`)

- Use function middleware (`createMiddleware({ type: "function" })`) for `createServerFn` call chains.
- Compose middleware arrays for shared policies, then keep the server function body focused on feature logic.
- Prefer middleware factories when policy parameters vary by call site (for example role or permission requirements).

### Error and Response Contract

- Middleware that owns HTTP denial paths should return a stable JSON payload and status code contract.
- Use clear separation between operational/configuration failures (`503` style responses) and authorization failures (`401`/`403`).
- Prefer a shared error middleware to translate typed exceptions (invalid JSON, invalid input schema, output validation failures) into consistent JSON + HTTP status responses.
- Keep this contract consistent across all CLI and API entry points.
