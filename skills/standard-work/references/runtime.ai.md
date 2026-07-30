# Runtime AI

This document defines runtime guidance for AI/LLM usage in Worker apps in this repo.

## Direction

- Keep AI calls inside app-local server functions under `src/server/`.
- Treat model output as untrusted input and validate before use.
- Prefer structured JSON output over free-form text for machine-consumed responses.
- Use Cloudflare Workers AI bindings via validated Worker `env`.
- Design prompts and schemas for determinism first, creativity second.
- Keep domain-specific AI schemas, prompts, and input types in the domain layer (for example `src/domain/workouts/ai/`).
- Use `runAiPipeline` from `src/infra/ai/` for all AI calls so logging and audit hooks are consistent.

## Prompt Structure

- Use a stable system prompt that captures role, safety boundaries, and output expectations.
- Keep user prompts concise and data-driven (avoid embedding business logic in prose).
- Put hard requirements in schema and validators, not only in prompt text.
- Include only necessary context to reduce token cost and improve consistency.
- Version prompts for breaking behavior changes (for example `workout-v2`).
- Prefer Markdown section headers and bullet lists for prompt structure.
- Avoid XML-ish prompt wrappers as a default (`<context>`, `<rules>`, etc.): they add token overhead, invite pseudo-XML drift, and do not improve correctness compared to clear Markdown + schema validation.

## Prompt Guidance

Use explicit prompt contracts for reliability, especially in long-running or tool-using flows.

- Define explicit completion criteria and output contracts; make "done" testable.
- Keep outputs concise and information-dense, but do not omit required evidence or checks.
- Require dependency checks before action; do not skip prerequisite retrieval steps.
- For tool workflows, continue until task completion and verification both pass.
- If retrieval is empty/partial, run 1-2 fallback strategies before concluding no result.
- If required context is missing, do not guess; prefer lookup tooling, then ask one minimal clarifying question only when lookup cannot resolve it.
- Add a lightweight verification loop before finalize/action: requirement coverage, grounding, format conformance, and safety/permission checks for side effects.
- For strict formats, output only the requested format (for example JSON); avoid extra prose unless explicitly requested.
- Treat reasoning effort as a last-mile tuning knob; start with prompt/contract improvements and raise reasoning effort only when evals show clear need.

Recommended reusable blocks (as Markdown sections, not XML-ish tags):

- Output contract
- Tool persistence rules
- Dependency checks
- Completeness contract
- Empty-result recovery
- Verification loop

## Prompt Caching

Use prompt caching when large prompt sections are reused across many requests.

- Best candidates: long system instructions, stable policy text, shared domain context.
- Keep cached segments stable; frequent edits reduce cache effectiveness.
- Split dynamic inputs (user data, recent state) from static prompt blocks.
- Track cache hit rate and token usage to verify cost and latency impact.
- Invalidate or re-version caches when prompt semantics change.

Implementation notes for Cloudflare Workers AI:

- Follow the current Workers AI prompt caching guidance and model support matrix before relying on cache behavior.
- Prefer deterministic prompt assembly so identical static sections remain byte-for-byte stable.
- Log cache-relevant metadata (model id, prompt version, static segment hash) without logging sensitive prompt content.

## JSON Output With Zod and JSON Schema

Use JSON Schema for model-constrained output and Zod for runtime validation and typing.

1. Define a Zod schema as the source of truth for application code.
2. Derive or maintain an equivalent JSON Schema for model response constraints.
3. Request structured JSON output from the model using the JSON schema.
4. Parse and validate the model response with Zod before persistence or downstream use.

Example pattern:

```ts
import { z } from 'zod'

export const WorkoutOutput = z.object({
  name: z.string().min(1),
  whiteboardDescription: z.string().min(1),
  coachingNotes: z.string().min(1),
  difficulty: z.enum(['beginner', 'intermediate', 'advanced', 'rx']),
})

export type WorkoutOutput = z.infer<typeof WorkoutOutput>

export const workoutOutputJsonSchema = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    whiteboardDescription: { type: 'string' },
    coachingNotes: { type: 'string' },
    difficulty: {
      type: 'string',
      enum: ['beginner', 'intermediate', 'advanced', 'rx'],
    },
  },
  required: ['name', 'whiteboardDescription', 'coachingNotes', 'difficulty'],
} as const

export const parseWorkoutOutput = (value: unknown): WorkoutOutput => {
  return WorkoutOutput.parse(value)
}
```

Rules:

- Do not trust `response` shape without validation.
- Prefer narrow enums and bounded strings where possible.
- Reject invalid responses and return typed errors to callers.
- Avoid type assertions in normal paths; rely on schema parsing.

## AI Pipeline

All AI calls go through `runAiPipeline` in `src/infra/ai/pipeline.ts`. This gives every AI call consistent logging and optional audit hooks.

### Architecture

- **Infra** (`src/infra/ai/`): owns the pipeline, Cloudflare response parsing, reusable utilities (`parseJsonText`).
- **Domain** (`src/domain/workouts/ai/`): owns schemas, prompts, input types, and the domain function that calls the pipeline.

### Pipeline Modes

`runAiPipeline` has two modes selected by `response_type`:

- **`response_type: "text"` (default)** — for plain text or free-form responses. Returns `AiResultText` with a `text: string` field.
- **`response_type: "object"`** — for structured JSON responses (when using `response_format: json_schema`). Returns `AiResultObject` with a `data: unknown` field containing the already-parsed object. No `JSON.stringify` → `JSON.parse` round-trip.

### Text Pipeline Example

```ts
import { runAiPipeline } from '@/infra/ai'

const result = await runAiPipeline({
  model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
  messages: [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: userPrompt },
  ],
  max_tokens: 2048,
  temperature: 0.7,
  runner: await deps.readAiRunner(),
  logger: deps.makeLogger({ component: 'ai' }),
})

// result.mode === 'text', result.text is a string
console.log(result.text)
```

### Object Pipeline Example

```ts
import { runAiPipeline } from '@/infra/ai'

const result = await runAiPipeline({
  response_type: 'object',
  model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
  messages: [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: userPrompt },
  ],
  response_format: { type: 'json_schema', json_schema: myJsonSchema },
  max_tokens: 2048,
  temperature: 0.7,
  runner: await deps.readAiRunner(),
  logger: deps.makeLogger({ component: 'ai' }),
})

// result.mode === 'object', result.data is the parsed JSON object
const validated = myZodSchema.parse(result.data)
```

### Result Types

`AiResult` is a discriminated union on `mode`:

**`AiResultText`** (`mode: "text"`):
- `text`: extracted response string
- `raw`: the raw Cloudflare response
- `usage`: token counts if available

**`AiResultObject`** (`mode: "object"`):
- `data`: the response object (already parsed, not yet schema-validated)
- `raw`: the raw Cloudflare response
- `usage`: token counts if available

### Built-in Logging

The pipeline always logs:
- **Success** (`info`): model, durationMs, token usage
- **Error** (`error`): model, durationMs, error object

This is the outermost layer — it wraps the entire call including audit hooks.

### Audit Hooks

Audit hooks use a middleware-style pattern. Each hook receives the call context and a `next` function:

```ts
export type AiAuditHook = (
  context: AiCallContext,
  next: () => Promise<AiResult>
) => Promise<AiResult>
```

Hooks chain like Express middleware:

```
[log-success/audit-hooks] → [hook-N] → ... → [hook-1] → [core: runner.run]
```

Example — adding a timing audit hook:

```ts
const timingHook: AiAuditHook = async (context, next) => {
  const startedAt = performance.now()
  const result = await next()
  console.log(`AI call took ${performance.now() - startedAt}ms`)
  return result
}
```

Hooks are optional. If no hooks are provided, the pipeline runs the core call directly with built-in logging.

### Rules

- Always use `runAiPipeline` — do not call the AI runner directly.
- Use `response_type: "object"` when requesting structured JSON output; use `response_type: "text"` (or omit) for free-form text.
- Always validate `result.data` with Zod before use; the pipeline does not schema-validate.
- Domain code handles error mapping (for example, mapping "JSON Mode couldn't be met" to user-facing messages).
- Pass `makeLogger` through deps so the pipeline gets a scoped logger.
- Keep audit hooks lightweight; heavy processing should happen after the pipeline returns.

## Cloudflare Workers AI Notes

- Bind AI in Wrangler config (`ai.binding`) and validate it in app-local `WorkerEnv` schema.
- Keep model ids explicit in code and centralize them in a small constant module when reused.
- Set practical runtime limits (`max_tokens`, timeout, retries) per use case.
- Handle structured-output failures explicitly and return actionable errors.
- Keep PII and secrets out of prompts unless required and approved.

## Observability and Safety

- Log request metadata, model id, duration, token usage, and validation outcomes.
- Never log raw secrets; avoid logging full prompt/response bodies by default.
- Add fallback behavior for model failures (retry strategy, safe defaults, or user-facing retry guidance).
- Add evaluation fixtures for key prompts so behavior regressions are detectable.

## Related Docs

- `references/runtime.config.md`
- `references/runtime.logging.md`
- `references/packages.tanstackStart.md`
- `references/data.access.md`
- Active repository `AGENTS.md`, when present

External reference:

- OpenAI Prompt guidance: https://developers.openai.com/api/docs/guides/prompt-guidance/
