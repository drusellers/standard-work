# Change Plan: AI Pipeline Evolution for Inference Runs

**Status:** Design Phase  
**Review Date:** 2026-06-28 (3 month retention)

This document captures the design for evolving the `infra/ai` pipeline to integrate with the `inference_run`/`inference_run_turn` data model and support tool calling, streaming, and async queue-based processing.

## Current State

We have two separate pieces:

1. **`infra/ai`** (`apps/app/src/infra/ai/`): Synchronous AI pipeline with streaming primitives
2. **`inference` model** (`references/change.workoutGeneration.md`): Data model for tracking multi-turn AI conversations with tool support

## Design Goals

1. **Message History**: Pipeline accepts existing turns and generates new ones
2. **Tool Calling**: Support OpenAI-style tool calls with execution loop
3. **Streaming**: Emit events (turns, tool calls, progress) via generator syntax
4. **Persistence**: Results convertible to `inference_run`/`inference_run_turn` structures
5. **Queue Integration**: Works in both sync (API) and async (queue worker) contexts

## Design Decisions

### Structured Concurrency with Effection

The pipeline uses **Effection** `Operation` types throughout for structured concurrency. This provides:

- **Cancellation propagation**: When a parent scope is destroyed, child operations clean up properly
- **Resource safety**: Ensures LLM streams and tool executions don't leak
- **Composable effects**: Generator syntax makes the tool loop readable

```ts
// Returns full result when complete
function runInferencePipeline(input): Operation<InferencePipelineResult>;

// Yields events as they occur, returns final result
function* streamInferencePipeline(input): Operation<InferencePipelineResult, InferenceEvent>;
```

### Tool Return Values

Tools return **Zod-validated objects**, not strings:

```ts
// Tool executor signature
export type ToolExecutor<TOutput = unknown> = (
  name: string,
  args: Record<string, unknown>
) => Promise<TOutput> | TOutput;

// Registration includes validation schemas
register<TInput extends ZodSchema, TOutput>(
  tool: ToolDefinition & { inputSchema: TInput; outputSchema: ZodSchema<TOutput> },
  executor: (args: z.infer<TInput>) => Promise<TOutput> | TOutput
): void;
```

**Storage**: Tool results are serialized to JSON when stored in `inference_run_turn.content`:

```ts
const toolTurn = {
  role: 'tool',
  content: JSON.stringify(result), // Object -> JSON string
  toolCallId: toolCall.id,
  toolName: toolCall.function.name,
};
```

When building message history for the next LLM call, the JSON string is used directly (OpenAI expects string content for tool messages).

## Core Abstractions

### 1. Message Types (OpenAI-compatible)

```ts
// packages/inference/src/messages.ts
export type MessageRole = 'system' | 'user' | 'assistant' | 'tool';

export type ToolCall = {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string; // JSON string
  };
};

export type SystemMessage = {
  role: 'system';
  content: string;
};

export type UserMessage = {
  role: 'user';
  content: string;
};

export type AssistantMessage = {
  role: 'assistant';
  content: string | null;
  tool_calls?: ToolCall[];
};

export type ToolMessage = {
  role: 'tool';
  content: string;
  tool_call_id: string;
  name: string;
};

export type Message = SystemMessage | UserMessage | AssistantMessage | ToolMessage;

// Conversion to/from inference_run_turn format
export function fromTurn(turn: InferenceRunTurn): Message;
export function toTurn(message: Message, sequence: number): Omit<InferenceRunTurn, 'id' | 'createdAt'>;
```

### 2. Tool Definition & Execution

Tools return Zod-validated objects, which get serialized to JSON when stored in `tool` turns:

```ts
// packages/inference/src/tools.ts
import type { z, ZodSchema } from 'zod';

export type ToolParameter = {
  type: string;
  description?: string;
  enum?: string[];
  properties?: Record<string, ToolParameter>;
  required?: string[];
  items?: ToolParameter;
};

export type ToolDefinition = {
  type: 'function';
  function: {
    name: string;
    description: string;
    parameters: ToolParameter;
  };
};

// Tool executors return Zod-validated objects
export type ToolExecutor<TOutput = unknown> = (
  name: string,
  args: Record<string, unknown>
) => Promise<TOutput> | TOutput;

// Type-safe tool registration with validation
export class ToolRegistry {
  register<TInput extends ZodSchema, TOutput>(
    tool: ToolDefinition & { inputSchema: TInput; outputSchema: ZodSchema<TOutput> },
    executor: (args: z.infer<TInput>) => Promise<TOutput> | TOutput
  ): void;
  
  getDefinitions(): ToolDefinition[];
  
  // Validates args against input schema, executes, validates output against output schema
  async execute(name: string, argsJson: string): Promise<unknown>;
}
```

**Tool Turn Storage:**
- Tool executors return objects (Zod-validated)
- Stored in `inference_run_turn.content` as `JSON.stringify(result)`
- Retrieved and parsed when building message history for next LLM call

### 3. Streaming Events

```ts
// packages/inference/src/events.ts
export type InferenceEvent =
  | { type: 'turn_start'; sequence: number; role: MessageRole }
  | { type: 'turn_chunk'; sequence: number; content: string } // For streaming assistant tokens
  | { type: 'turn_complete'; sequence: number; turn: InferenceRunTurn }
  | { type: 'tool_call'; sequence: number; toolCall: ToolCall }
  | { type: 'tool_execute_start'; sequence: number; name: string }
  | { type: 'tool_execute_complete'; sequence: number; result: unknown; durationMs: number }
  | { type: 'iteration_complete'; iteration: number; maxIterations: number }
  | { type: 'complete'; output: unknown; totalTurns: number }
  | { type: 'error'; code: string; message: string; retryable: boolean };
```

## The Pipeline

### High-Level API

```ts
// packages/inference/src/pipeline.ts
import { Operation } from 'effection';

export type InferencePipelineInput = {
  // Identity
  inferenceRunId: string;
  userId: string;
  
  // Configuration
  modelId: string;
  type: 'workout_generation' | 'program_generation' | 'movement_analysis';
  
  // Conversation state
  messages: Message[]; // Existing turns converted to messages
  systemPrompt?: string;
  
  // Tooling
  tools?: ToolDefinition[];
  toolExecutor?: ToolExecutor;
  maxToolIterations?: number;
  
  // Cloudflare bindings
  runner: AiRunner;
  logger: AppLogger;
  
  // Streaming control
  enableStreaming?: boolean;
};

export type InferencePipelineResult = {
  success: true;
  output: unknown;
  turns: InferenceRunTurn[]; // New turns generated (not including input messages)
  tokenUsage: AiUsage;
} | {
  success: false;
  error: { code: string; message: string; retryable: boolean };
  turns: InferenceRunTurn[]; // Partial turns before failure
  tokenUsage: AiUsage;
};

// Synchronous version - returns full result
export function runInferencePipeline(
  input: InferencePipelineInput
): Operation<InferencePipelineResult>;

// Streaming version - yields events, returns final result
export function* streamInferencePipeline(
  input: InferencePipelineInput
): Operation<InferencePipelineResult, InferenceEvent>;
```

### Implementation Sketch

```ts
// packages/inference/src/pipeline.ts
import { withResolvers } from '@/lib/promise';

export function* streamInferencePipeline(
  input: InferencePipelineInput
): Operation<InferencePipelineResult, InferenceEvent> {
  const { resolve, reject, promise } = withResolvers<InferencePipelineResult>();
  
  const newTurns: InferenceRunTurn[] = [];
  let sequence = input.messages.length;
  let totalUsage: AiUsage = { promptTokens: 0, completionTokens: 0, totalTokens: 0 };
  
  try {
    const maxIterations = input.maxToolIterations ?? 5;
    
    for (let iteration = 0; iteration < maxIterations; iteration++) {
      // Build messages array including any tool responses from previous iteration
      const messages = buildMessageHistory(input.messages, newTurns, input.systemPrompt);
      
      // Emit iteration event
      yield { type: 'iteration_complete', iteration, maxIterations };
      
      // Start assistant turn
      yield { type: 'turn_start', sequence, role: 'assistant' };
      
      // Make LLM call with tool support
      const response: { 
        content: string | null; 
        tool_calls?: ToolCall[];
        usage?: AiUsage;
        raw: unknown;
      } = input.enableStreaming
        ? yield* callWithStreaming(input, messages, sequence)
        : yield* callWithPolling(input, messages);
      
      // Track tokens
      if (response.usage) {
        totalUsage = addUsage(totalUsage, response.usage);
      }
      
      // Create assistant turn
      const assistantTurn: Omit<InferenceRunTurn, 'id' | 'createdAt'> = {
        inferenceRunId: input.inferenceRunId,
        sequence: sequence++,
        role: 'assistant',
        content: response.content,
        toolCalls: response.tool_calls?.map(tc => ({
          id: tc.id,
          type: 'function',
          function: {
            name: tc.function.name,
            arguments: tc.function.arguments,
          }
        })) ?? null,
        toolCallId: null,
        toolName: null,
        tokenUsage: response.usage ?? null,
        rawResponse: response.raw as Record<string, unknown>,
      };
      
      yield { type: 'turn_complete', sequence: assistantTurn.sequence, turn: assistantTurn as InferenceRunTurn };
      newTurns.push(assistantTurn as InferenceRunTurn);
      
      // If no tool calls, we're done
      if (!response.tool_calls || response.tool_calls.length === 0) {
        const output = parseOutput(input.type, response.content);
        yield { type: 'complete', output, totalTurns: newTurns.length };
        
        resolve({
          success: true,
          output,
          turns: newTurns,
          tokenUsage: totalUsage,
        });
        return promise;
      }
      
      // Execute tool calls
      for (const toolCall of response.tool_calls) {
        yield { type: 'tool_call', sequence, toolCall };
        
        const executeStart = performance.now();
        yield { type: 'tool_execute_start', sequence, name: toolCall.function.name };
        
        const result = yield* call(input.toolExecutor!, toolCall.function.name, JSON.parse(toolCall.function.arguments));
        const durationMs = performance.now() - executeStart;
        
        yield { type: 'tool_execute_complete', sequence, result, durationMs };
        
        // Create tool turn - serialize result to JSON for storage
        const toolTurn: Omit<InferenceRunTurn, 'id' | 'createdAt'> = {
          inferenceRunId: input.inferenceRunId,
          sequence: sequence++,
          role: 'tool',
          content: JSON.stringify(result), // Tool returns object, we serialize for storage
          toolCalls: null,
          toolCallId: toolCall.id,
          toolName: toolCall.function.name,
          tokenUsage: null,
          rawResponse: null,
        };
        
        yield { type: 'turn_complete', sequence: toolTurn.sequence, turn: toolTurn as InferenceRunTurn };
        newTurns.push(toolTurn as InferenceRunTurn);
      }
    }
    
    throw new Error('Max tool iterations exceeded');
    
  } catch (error) {
    const errorResult = {
      code: error instanceof Error ? error.name : 'UNKNOWN',
      message: error instanceof Error ? error.message : String(error),
      retryable: isRetryableError(error),
    };
    
    yield { type: 'error', ...errorResult };
    
    resolve({
      success: false,
      error: errorResult,
      turns: newTurns,
      tokenUsage: totalUsage,
    });
  }
  
  return promise;
}

// Streaming LLM call that yields chunks
function* callWithStreaming(
  input: InferencePipelineInput,
  messages: Message[],
  sequence: number
): Operation<{ content: string | null; tool_calls?: ToolCall[]; usage?: AiUsage; raw: unknown }> {
  // Use existing streamAiTokens but add tool call detection
  const chunks: string[] = [];
  
  for (const chunk of yield* streamAiTokens({
    model: input.modelId,
    messages: messages as Array<{ role: string; content: string }>,
    max_tokens: 4096,
    temperature: 0.7,
    runner: input.runner,
  })) {
    chunks.push(chunk);
    yield { type: 'turn_chunk', sequence, content: chunk };
  }
  
  const fullText = chunks.join('');
  const parsed = parseJsonText(fullText); // Helper from existing pipeline
  
  return {
    content: typeof parsed === 'object' && parsed !== null && 'content' in parsed 
      ? String(parsed.content) 
      : fullText,
    tool_calls: parsed && typeof parsed === 'object' && 'tool_calls' in parsed 
      ? parsed.tool_calls as ToolCall[] 
      : undefined,
    raw: parsed,
  };
}

// Non-streaming LLM call
function* callWithPolling(
  input: InferencePipelineInput,
  messages: Message[]
): Operation<{ content: string | null; tool_calls?: ToolCall[]; usage?: AiUsage; raw: unknown }> {
  // Use existing runAiPipeline but add tool support to response_format
  const result = yield* runAiPipeline({
    response_type: 'object',
    model: input.modelId,
    messages: messages as Array<{ role: string; content: string }>,
    response_format: { 
      type: 'json_object',
      // Allow tool_calls in response schema when tools provided
    },
    max_tokens: 4096,
    temperature: 0.7,
    runner: input.runner,
    logger: input.logger,
  });
  
  const data = result.data as Record<string, unknown>;
  
  return {
    content: data.content as string | null,
    tool_calls: data.tool_calls as ToolCall[] | undefined,
    usage: result.usage,
    raw: result.raw,
  };
}
```

```ts
// Helper: Build message history from base messages + generated turns
function buildMessageHistory(
  baseMessages: Message[],
  newTurns: InferenceRunTurn[],
  systemPrompt?: string
): Message[] {
  const messages: Message[] = [...baseMessages];

  if (systemPrompt && !messages.some((m) => m.role === 'system')) {
    messages.unshift({ role: 'system', content: systemPrompt });
  }

  for (const turn of newTurns.sort((a, b) => a.sequence - b.sequence)) {
    if (turn.role === 'assistant') {
      const msg: AssistantMessage = {
        role: 'assistant',
        content: turn.content,
      };
      if (turn.toolCalls) {
        msg.tool_calls = turn.toolCalls.map((tc) => ({
          id: tc.id,
          type: tc.type,
          function: {
            name: tc.function.name,
            arguments: tc.function.arguments,
          },
        }));
      }
      messages.push(msg);
    } else if (turn.role === 'tool') {
      messages.push({
        role: 'tool',
        content: turn.content, // Already JSON string from storage
        tool_call_id: turn.toolCallId!,
        name: turn.toolName!,
      });
    }
  }

  return messages;
}

// Helper: Add usage counters
function addUsage(a: AiUsage, b?: AiUsage): AiUsage {
  if (!b) return a;
  return {
    promptTokens: a.promptTokens + b.promptTokens,
    completionTokens: a.completionTokens + b.completionTokens,
    totalTokens: a.totalTokens + b.totalTokens,
  };
}

// Helper: Check if error is retryable
function isRetryableError(error: unknown): boolean {
  // Network errors, rate limits, and 5xx errors are retryable
  if (error instanceof Error) {
    if (error.message.includes('rate limit')) return true;
    if (error.message.includes('timeout')) return true;
    if (error.message.includes('5')) return true; // crude but works for now
  }
  return false;
}
```

## Integration Points

### 1. Repository Adapter

```ts
// packages/inference/src/repositoryAdapter.ts
import { type InferenceRepository } from './repository';

export function createEventPersister(
  repo: InferenceRepository,
  inferenceRunId: string
): (event: InferenceEvent) => Promise<void> {
  return async (event) => {
    switch (event.type) {
      case 'turn_complete':
        await repo.addTurn(event.turn);
        break;
        
      case 'complete':
        await repo.updateOutput(inferenceRunId, event.output);
        await repo.updateStatus(inferenceRunId, 'completed', {
          completedAt: new Date(),
        });
        break;
        
      case 'error':
        await repo.updateError(inferenceRunId, {
          code: event.code,
          message: event.message,
          retryable: event.retryable,
        });
        await repo.updateStatus(inferenceRunId, 'failed');
        break;
    }
  };
}
```

### 2. Queue Worker Integration

```ts
// apps/queue-worker/src/handlers/inference.ts
import { streamInferencePipeline, createEventPersister } from '@chalkmd/inference';
import { call } from 'effection';

export async function handleInferenceMessage(
  message: InferenceMessage,
  env: WorkerEnv
): Promise<void> {
  const repo = createInferenceRepository(env.DB);
  const run = await repo.getByIdWithTurns(message.inferenceId);
  
  if (!run) throw new Error(`Inference run not found: ${message.inferenceId}`);
  
  // Convert existing turns to messages
  const messages = run.turns
    .sort((a, b) => a.sequence - b.sequence)
    .map(fromTurn);
  
  // Set up persister for DO events
  const persister = createEventPersister(repo, message.inferenceId);
  
  // Get DO stub for streaming
  const coordinatorId = run.coordinatorId;
  const coordinator = coordinatorId 
    ? env.INFERENCE_COORDINATOR_DO.get(env.INFERENCE_COORDINATOR_DO.idFromString(coordinatorId))
    : null;
    
  await repo.updateStatus(message.inferenceId, 'processing');
  
  // Run pipeline with event handling
  const result = await call(function* () {
    const pipeline = streamInferencePipeline({
      inferenceRunId: message.inferenceId,
      tenantId: message.tenantId,
      modelId: run.modelId,
      type: run.type,
      messages,
      systemPrompt: getSystemPrompt(run.type),
      tools: getToolsForType(run.type),
      toolExecutor: createToolExecutor(env),
      maxToolIterations: 5,
      runner: env.AI,
      logger: console,
      enableStreaming: false, // Queue uses polling for stability
    });
    
    // Consume events, persist to DB, and forward to DO
    for (const event of yield* pipeline) {
      // Persist to database
      await persister(event);
      
      // Forward to DO for client streaming
      if (coordinator) {
        await coordinator.fetch('http://internal/event', {
          method: 'POST',
          body: JSON.stringify(event),
        });
      }
    }
    
    return yield* pipeline;
  });
  
  if (!result.success) {
    throw new Error(result.error.message);
  }
  
  // Create domain entities (workout, etc.)
  await createDomainEntities(run, result.output, env);
}
```

### 3. API Route (Synchronous with Optional Streaming)

```ts
// apps/app/src/server/inference/stream.ts
import { createServerFn } from '@tanstack/react-start';
import { streamInferencePipeline } from '@chalkmd/inference';

export const streamInference = createServerFn({ method: 'GET' })
  .handler(async ({ context, request }) => {
    const { env, user } = context;
    const url = new URL(request.url);
    const inferenceId = url.searchParams.get('inferenceId');
    
    if (!inferenceId) throw new Error('inferenceId required');
    
    const repo = createInferenceRepository(env.DB);
    const run = await repo.getByIdWithTurns(inferenceId);
    
    if (!run || run.requestedByUserId !== user.id) {
      throw new Error('Not found');
    }
    
    // If already complete, return cached result
    if (run.status === 'completed') {
      return new Response(JSON.stringify({ complete: true, output: run.output }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    
    // If still queued, return status
    if (run.status === 'queued' || run.status === 'pending') {
      return new Response(JSON.stringify({ status: run.status }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    
    // If processing and we have a coordinator, use DO streaming
    if (run.coordinatorId) {
      const coordinator = env.INFERENCE_COORDINATOR_DO.get(
        env.INFERENCE_COORDINATOR_DO.idFromString(run.coordinatorId)
      );
      return coordinator.fetch('http://internal/stream');
    }
    
    // Fallback: synchronous execution (for small/simple inferences)
    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      async start(controller) {
        const messages = run.turns.map(fromTurn);
        
        for await (const event of streamInferencePipeline({
          inferenceRunId: inferenceId,
          tenantId: run.tenantId,
          modelId: run.modelId,
          type: run.type,
          messages,
          runner: env.AI,
          logger: console,
          enableStreaming: true,
        })) {
          controller.enqueue(encoder.encode(formatSseEvent(event)));
          
          // Persist turn events
          if (event.type === 'turn_complete') {
            await repo.addTurn(event.turn);
          }
        }
        
        controller.enqueue(SSE_DONE);
        controller.close();
      },
    });
    
    return new Response(stream, { headers: sseHeaders });
  });
```

## Migration Path

### Phase 1: Core Pipeline (Current PR)
- [ ] Add `Message` types and conversion utilities
- [ ] Add `ToolRegistry` for tool execution
- [ ] Add `InferenceEvent` types
- [ ] Implement `streamInferencePipeline` with Effection
- [ ] Add `createEventPersister` adapter

### Phase 2: Queue Worker Integration
- [ ] Refactor queue worker to use new pipeline
- [ ] Add tool definitions for workout generation
- [ ] Wire up DO event forwarding

### Phase 3: API Streaming
- [ ] Add `/api/inference/stream` route
- [ ] Implement DO-based streaming
- [ ] Add React hook for consuming stream

## Research in Progress

### Streaming JSON with Tool Calls

When streaming responses that may include `tool_calls`, we need to handle:
- Partial tool call IDs
- Partial function names  
- Partial arguments (JSON object streaming)

**Approaches being explored:**
1. **Schema-aware streaming parser**: Extend `repairJsonStream` to understand the expected response schema and yield partial tool_calls as they become valid
2. **Two-phase streaming**: First stream detects if response is text or tool_calls, then switches to appropriate parser
3. **Buffer-until-valid**: Accumulate chunks until we have valid JSON, then yield complete tool_calls

**Test scenarios for demo:**
- Assistant responds with plain text (no tools)
- Assistant calls single tool
- Assistant calls multiple tools in parallel
- Assistant chains tool calls (calls tool, gets result, calls another)

### DO Lifecycle Management

**Questions being explored:**
- How long does a DO stay alive after last WebSocket disconnect?
- Can we use DO alarms to schedule cleanup?
- Should we store event history in DO for reconnection replay?
- What's the cost model for DOs that are idle but not hibernated?

**Potential approaches:**
1. **Immediate hibernation**: Close DO after stream completes, client reconnects hit D1 for state
2. **Buffered hibernation**: Keep DO alive for 30s after disconnect for reconnection window
3. **Persistent replay**: Store events in DO storage, replay on reconnect, alarm cleanup after 5min

## Related Docs

- `references/change.workoutGeneration.md` — Full inference architecture with queues and DOs
- `references/packages.effection.md` — Structured concurrency patterns
- `apps/app/src/infra/ai/pipeline.ts` — Current sync pipeline implementation
- `apps/app/src/infra/ai/streaming.ts` — Current streaming primitives
