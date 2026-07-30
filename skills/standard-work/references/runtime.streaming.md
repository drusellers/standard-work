# Runtime Streaming

This document defines guidance for server-sent events (SSE) and streaming responses in this repo.

## Direction

- Use SSE for unidirectional server-to-client streaming (AI generation progress, real-time updates).
- Prefer `fetch` + `ReadableStream` over `EventSource` when the client needs to POST a request body.
- Use TanStack Start server route handlers (`createFileRoute` with `server.handlers`) for SSE endpoints — not `createServerFn`, which does not support streaming responses.
- Clean up streams on client disconnect via `request.signal.addEventListener("abort", ...)`.

## SSE Protocol

Server-Sent Events use plain HTTP with specific headers and a line-based text format.

### Response Headers

```http
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
X-Accel-Buffering: no
```

### Event Format

Each event is one or more `field: value` lines terminated by a blank line:

```
data: {"type":"chunk","partial":"{\"name\":\"Eng..."}\n\n
```

Named events (optional):

```
event: workout\ndata: {"name":"Engine Builder"}\n\n
```

### Termination

Signal end-of-stream with:

```
data: [DONE]\n\n
```

## Server-Side Pattern (TanStack Start)

Use a TanStack Start server route handler that returns a `Response` with a `ReadableStream` body:

```ts
import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/example-stream")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const encoder = new TextEncoder();

        const stream = new ReadableStream({
          async start(controller) {
            // Send events as they become available
            controller.enqueue(
              encoder.encode(`data: ${JSON.stringify({ type: "chunk", value: "hello" })}\n\n`),
            );

            // Signal completion
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            controller.close();
          },
          cancel() {
            // Client disconnected — cleanup resources
          },
        });

        request.signal.addEventListener("abort", () => {
          // Alternative cleanup hook
        });

        return new Response(stream, {
          headers: {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
            "X-Accel-Buffering": "no",
          },
        });
      },
    },
  },
});
```

### Key Details

- The route file uses TanStack flat routes. A file named `api.example-stream.ts` maps to `/api/example-stream`.
- The handler receives the raw `Request` object — parse the body manually with `await request.json()`.
- Validate input with Zod before processing.
- The `ReadableStream` `start` callback does the async work. Use `controller.enqueue()` to push SSE-formatted bytes.
- Handle `request.signal` abort for cleanup when the client disconnects.

## Client-Side Pattern

Use `fetch` + `response.body.getReader()` for POST-based SSE:

```ts
const response = await fetch("/api/example-stream", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(input),
});

const reader = response.body!.getReader();
const decoder = new TextDecoder();
let buffer = "";

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  buffer += decoder.decode(value, { stream: true });

  const lines = buffer.split("\n");
  buffer = lines.pop() ?? "";

  for (const line of lines) {
    if (line.startsWith("data: ")) {
      const data = line.slice(6);
      if (data === "[DONE]") return;

      const event = JSON.parse(data);
      // Handle event by type
    }
  }
}
```

### Why Not EventSource?

`EventSource` only supports GET requests and cannot send a request body. For AI generation endpoints that require input (prompts, parameters), use `fetch` with streaming reads.

## JSON Streaming With Repair

When streaming structured JSON from an LLM, the output arrives incrementally and may be incomplete at any point. Use `IncrementalJsonRepair` from `repair-json-stream` to produce valid JSON at every step:

```ts
import { IncrementalJsonRepair } from "repair-json-stream/incremental";

const repairer = new IncrementalJsonRepair();
let repaired = "";

for await (const token of aiTokenStream) {
  repaired += repairer.push(token);
  // repaired is always valid JSON (with auto-closed brackets)
  const partial = JSON.parse(repaired);
}
repaired += repairer.end();
```

Pair with Zod validation to emit confirmed-structurally-valid events once the full response is parseable.

## Related Docs

- `references/runtime.ai.md` — AI call patterns and JSON output conventions
- `references/packages.tanstackStart.md` — TanStack Start server function patterns
- `references/runtime.logging.md` — request logging middleware
