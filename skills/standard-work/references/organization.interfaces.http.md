# HTTP Interface Catalog

This page defines the shared HTTP interface contract for ChalkMD server routes.

Use this doc when adding or reviewing HTTP endpoints, especially list/query endpoints that need pagination.

## Purpose

- Keep request and response contracts consistent across app and CLI-backed HTTP endpoints.
- Standardize pagination behavior so clients can reuse one integration pattern.
- Keep endpoint behavior SQLite-friendly while preserving stable ordering semantics.

## Related Docs

- Route inventory and URL shape: `references/organization.routes.md`
- CLI command to HTTP mapping: `references/organization.interfaces.cli.md`
- TanStack server boundary validation and error handling: `references/packages.tanstackStart.md`

## HTTP Contract Baseline

- Validate all client input at the route boundary (query params, body, headers as needed).
- Return JSON payloads with stable key names and predictable error shapes.
- For auth failures, prefer JSON `401`/`403` responses over redirects for API routes.
- Keep list responses generic at the top level with `items` as the data key.

## Pagination Standard (Cursor-Based)

### Direction

- Pagination is cursor-based (keyset pagination), not offset-based.
- Cursors are opaque to clients and encoded (base64url of JSON payload).
- List responses use this top-level shape:

```json
{
  "items": [],
  "pageInfo": {
    "pageSize": 20,
    "returnedCount": 20,
    "currentCursor": null,
    "nextCursor": "eyJ2IjoxLCJrZXlzIjp7ImNyZWF0ZWRBdCI6MTcxMTc4MzYwMDAwMCwiaWQiOiIxMjMifX0",
    "previousCursor": null,
    "hasNextPage": true,
    "hasPreviousPage": false,
    "currentPage": 1,
    "totalCount": 138
  }
}
```

### Query Parameters

- `limit`: requested page size (bounded; recommended default `20`, max `100`).
- `cursor`: opaque encoded cursor from `pageInfo.nextCursor` or `pageInfo.previousCursor`.
- `includeTotal`: optional boolean; when `true`, server computes `totalCount`.
- `includePage`: optional boolean; when `true`, server computes `currentPage`.

### Page Info Fields

- `pageSize`: effective page size used by the server.
- `returnedCount`: number of rows in `items`.
- `currentCursor`: cursor provided in the request, otherwise `null`.
- `nextCursor`: cursor for the next page, otherwise `null`.
- `previousCursor`: cursor for the previous page when supported, otherwise `null`.
- `hasNextPage`: `true` when more rows exist after this page.
- `hasPreviousPage`: `true` when request was not the first page (or reverse cursor logic confirms prior rows).
- `currentPage`: nullable number; return when requested and computed, otherwise `null`.
- `totalCount`: nullable number; return when requested and computed, otherwise `null`.

### Cursor Encoding

Cursor payload (before encoding) should include:

- `v`: cursor schema version.
- `keys`: last row sort keys from the current page.
- `order`: sort contract identifier (recommended).

Recommended payload example:

```json
{
  "v": 1,
  "order": "createdAt:desc,id:desc",
  "keys": {
    "createdAt": 1711783600000,
    "id": "run_01HV..."
  }
}
```

Encoding algorithm:

1. JSON stringify payload.
2. UTF-8 encode.
3. Base64url encode.

Decoding failures or cursor schema mismatches should return `400` with a typed invalid-cursor error.

### SQLite-Safe Query Pattern

Use a stable tie-broken ordering and keyset predicate:

```sql
SELECT *
FROM inference_run
WHERE requested_by_user_id = ?
  AND (
    created_at < ?
    OR (created_at = ? AND id < ?)
  )
ORDER BY created_at DESC, id DESC
LIMIT ?;
```

- Fetch `limit + 1` rows to derive `hasNextPage`, then trim to `limit` for `items`.
- Generate `nextCursor` from the last returned item after trimming.
- Reuse the exact same filter scope for `COUNT(*)` queries used by `totalCount`.
- Keep `created_at` values in a consistent format so comparisons remain stable.

### Current Page and Total Count Guidance

- `totalCount` is useful but can be expensive; gate it behind `includeTotal=true`.
- `currentPage` is not intrinsic to cursor pagination and can drift as data changes.
- Return `currentPage` when explicitly requested (`includePage=true`) and computed.
- On first page requests (no cursor), `currentPage` may safely be `1`.
- When not requested or not computed, return `currentPage: null` and `totalCount: null`.

## Error Contract for Pagination Inputs

- Invalid `limit` -> `400` with validation details.
- Invalid or malformed `cursor` -> `400` invalid cursor response.
- Unsupported cursor version or order contract -> `400` invalid cursor response.

Keep error shaping aligned with shared route middleware in `references/packages.tanstackStart.md`.
