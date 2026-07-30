# Runtime Logging

## Direction

- We use `pino` for structured application logging.
- Request logging is implemented as TanStack Start global request middleware.
- This gives us one place to evolve logging behavior as requirements grow.

## Current Middleware

- App middleware: `apps/app/src/server/requestLoggingMiddleware.ts`
- Marketing middleware: `apps/marketing/src/server/requestLoggingMiddleware.ts`
- Global registration:
  - `apps/app/src/start.ts`
  - `apps/marketing/src/start.ts`

## Current Request Log Shape

Each request log currently includes these keys:

- `method`: HTTP method (for example `GET`, `POST`)
- `route`: TanStack Start request pathname
- `requestId`: request correlation id (from `x-request-id` or generated UUID)
- `statusCode`: response status code
- `requestSizeBytes`: request `content-length` when available, otherwise `null`
- `responseSizeBytes`: response `content-length` when available, otherwise `null`
- `durationMs`: request duration in milliseconds

The log message is currently formatted as:

- `<METHOD> <ROUTE>`

## Notes

- Request/response size relies on `content-length` headers, so values can be `null` when the header is absent.
- Middleware also writes `x-request-id` to the response so clients can correlate a response with logs.
- This is intentionally minimal and designed to be expanded with additional standard keys over time.
