# Change Plan: Workout Generation

**Status:** Planned  
**Review Date:** 2026-06-27 (3 month retention)

This document captures the architectural plan for asynchronous workout generation using Cloudflare Queues and Durable Objects. The goal is to avoid the 60-second request timeout while providing real-time progress updates to the client.

## Problem Statement

Synchronous LLM calls for workout generation can exceed Cloudflare's 60-second request timeout, especially for complex multi-day training blocks. We need an architecture that:

1. Accepts generation requests immediately without blocking
2. Processes generation asynchronously in a background worker
3. Streams progress/events back to the client in real-time
4. Persists the final result to the database

## Phase 1: Inference Model

Build the data model for tracking AI inference requests. This model captures the user's generation request, tracks its lifecycle, stores conversation turns (messages), and tracks tool calls.

### Data Model

#### inference_run

The parent record tracking an inference request from start to finish.

```ts
interface InferenceRun {
  id: string;                    // ULID, primary key
  tenantId: string;              // For tenant isolation
  requestedByUserId: string;     // Who initiated
  
  // Inference configuration
  type: 'workout_generation' | 'program_generation' | 'movement_analysis';
  modelId: string;               // e.g., "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
  
  // Initial user request (summarized)
  input: Record<string, unknown>; // Zod-validated input parameters, JSONB
  
  // Final output (after all turns complete)
  output: Record<string, unknown> | null; // Zod-validated output, JSONB
  
  // Lifecycle tracking
  status: 'pending' | 'queued' | 'processing' | 'completed' | 'failed' | 'cancelled';
  
  // Turn tracking
  turnCount: number;             // Number of turns (messages) in this run
  
  // Timing
  createdAt: Date;
  queuedAt: Date | null;
  startedAt: Date | null;
  completedAt: Date | null;
  
  // Aggregated metadata (sum of all turns)
  tokenUsage: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  } | null;
  
  // Error handling
  error: {
    code: string;
    message: string;
    retryable: boolean;
  } | null;
  
  // Note: Domain entities link TO inference_run via inferenceRunId
  // This supports 1:N (one inference creates many items) without polymorphic FKs
  
  // Phase 3: Durable Object coordination
  coordinatorId: string | null;  // DO ID for streaming (nullable until Phase 3)
}
```

#### inference_run_turn

Individual messages/turns in the conversation. Maps to OpenAI's message format with roles (system, user, assistant, tool).

```ts
interface InferenceRunTurn {
  id: string;                    // ULID
  inferenceRunId: string;        // FK to inference_run
  
  // Message metadata
  sequence: number;              // 0, 1, 2... order in conversation
  role: 'system' | 'user' | 'assistant' | 'tool';
  
  // Content (null if role=assistant with tool_calls only)
  content: string | null;
  
  // Tool calls (only for role='assistant')
  // Array of {id, type, function: {name, arguments}}
  toolCalls: Array<{
    id: string;
    type: 'function';
    function: {
      name: string;
      arguments: string;         // JSON string of arguments
    };
  }> | null;
  
  // Tool response fields (only for role='tool')
  toolCallId: string | null;     // References the assistant's tool call
  toolName: string | null;       // Function name for convenience
  
  // Metadata
  tokenUsage: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  } | null;
  
  // Timing
  createdAt: Date;
  
  // Optional: raw response for debugging
  rawResponse: Record<string, unknown> | null;
}
```

### Zod Schemas

```ts
// packages/inference/src/schemas.ts
import { z } from 'zod';

export const InferenceStatus = z.enum([
  'pending',
  'queued', 
  'processing',
  'completed',
  'failed',
  'cancelled'
]);

export const InferenceType = z.enum([
  'workout_generation',
  'program_generation',
  'movement_analysis'
]);

export const MessageRole = z.enum(['system', 'user', 'assistant', 'tool']);

export const ToolCall = z.object({
  id: z.string(),
  type: z.literal('function'),
  function: z.object({
    name: z.string(),
    arguments: z.string(), // JSON string
  }),
});

export const InferenceRunTurn = z.object({
  id: z.string(),
  inferenceRunId: z.string(),
  sequence: z.number().int().nonnegative(),
  role: MessageRole,
  content: z.string().nullable(),
  toolCalls: z.array(ToolCall).nullable(),
  toolCallId: z.string().nullable(),
  toolName: z.string().nullable(),
  tokenUsage: z.object({
    promptTokens: z.number(),
    completionTokens: z.number(),
    totalTokens: z.number(),
  }).nullable(),
  createdAt: z.date(),
  rawResponse: z.record(z.unknown()).nullable(),
});

export type InferenceRunTurn = z.infer<typeof InferenceRunTurn>;

export const InferenceRun = z.object({
  id: z.string(),
  tenantId: z.string(),
  requestedByUserId: z.string(),
  type: InferenceType,
  modelId: z.string(),
  input: z.record(z.unknown()),
  output: z.record(z.unknown()).nullable(),
  status: InferenceStatus,
  turnCount: z.number().int().nonnegative(),
  createdAt: z.date(),
  queuedAt: z.date().nullable(),
  startedAt: z.date().nullable(),
  completedAt: z.date().nullable(),
  tokenUsage: z.object({
    promptTokens: z.number(),
    completionTokens: z.number(),
    totalTokens: z.number(),
  }).nullable(),
  error: z.object({
    code: z.string(),
    message: z.string(),
    retryable: z.boolean(),
  }).nullable(),
  // Removed: entityType, entityId - see "Why Items Link to Inference" section
  coordinatorId: z.string().nullable(),
});

export type InferenceRun = z.infer<typeof InferenceRun>;

// Input schemas per inference type
export const WorkoutGenerationInput = z.object({
  type: z.literal('workout_generation'),
  parameters: z.object({
    durationMinutes: z.number().min(5).max(180),
    targetEnergySystem: z.enum(['aerobic', 'lactic', 'alactic', 'mixed']),
    equipment: z.array(z.string()),
    movementPatterns: z.array(z.string()).optional(),
    difficulty: z.enum(['beginner', 'intermediate', 'advanced', 'rx']).optional(),
    constraints: z.string().optional(),
  }),
});
```

### Repository Pattern

```ts
// packages/inference/src/repository.ts
import { and, desc, eq, sql } from 'drizzle-orm';
import { drizzle, type DrizzleD1Database } from 'drizzle-orm/d1';

export interface InferenceRepository {
  // InferenceRun operations
  create(run: Omit<InferenceRun, 'id' | 'createdAt' | 'turnCount'>): Promise<InferenceRun>;
  getById(id: string): Promise<InferenceRun | null>;
  getByIdWithTurns(id: string): Promise<(InferenceRun & { turns: InferenceRunTurn[] }) | null>;
  getByUser(userId: string, options: { limit: number; cursor?: string }): Promise<PaginatedResult<InferenceRun>>;
  updateStatus(id: string, status: InferenceStatus, updates?: Partial<InferenceRun>): Promise<void>;
  updateOutput(id: string, output: Record<string, unknown>): Promise<void>;
  updateError(id: string, error: InferenceRun['error']): Promise<void>;
  
  // InferenceRunTurn operations
  addTurn(turn: Omit<InferenceRunTurn, 'id' | 'createdAt'>): Promise<InferenceRunTurn>;
  getTurnsByInferenceRunId(inferenceRunId: string): Promise<InferenceRunTurn[]>;
}

// D1 implementation in apps/api/src/repositories/inference.ts
export class D1InferenceRepository implements InferenceRepository {
  constructor(private db: DrizzleD1Database) {}

  static fromD1(binding: D1Database): D1InferenceRepository {
    return new D1InferenceRepository(drizzle(binding));
  }
  
  async create(run: Omit<InferenceRun, 'id' | 'createdAt' | 'turnCount'>): Promise<InferenceRun> {
    const id = generateUlid();
    const createdAt = new Date();

    await this.db.insert(inferenceRun).values({
      id,
      tenantId: run.tenantId,
      requestedByUserId: run.requestedByUserId,
      type: run.type,
      modelId: run.modelId,
      input: run.input,
      status: run.status,
      turnCount: 0,
      createdAt,
      coordinatorId: run.coordinatorId,
    });
      
    return { ...run, id, createdAt, turnCount: 0 };
  }
  
  async addTurn(turn: Omit<InferenceRunTurn, 'id' | 'createdAt'>): Promise<InferenceRunTurn> {
    const id = generateUlid();
    const createdAt = new Date();

    await this.db.insert(inferenceRunTurn).values({
      id,
      inferenceRunId: turn.inferenceRunId,
      sequence: turn.sequence,
      role: turn.role,
      content: turn.content,
      toolCalls: turn.toolCalls,
      toolCallId: turn.toolCallId,
      toolName: turn.toolName,
      tokenUsage: turn.tokenUsage,
      createdAt,
      rawResponse: turn.rawResponse,
    });
      
    return { ...turn, id, createdAt };
  }
  
  async incrementTurnCount(id: string, tokens: InferenceRun['tokenUsage']): Promise<void> {
    const promptTokens = tokens?.promptTokens ?? 0;
    const completionTokens = tokens?.completionTokens ?? 0;
    const totalTokens = tokens?.totalTokens ?? 0;

    // Keep this atomic using SQL expressions inside Drizzle's SQL-like update API.
    await this.db
      .update(inferenceRun)
      .set({
        turnCount: sql`${inferenceRun.turnCount} + 1`,
        tokenUsage: sql`
          json_patch(
            coalesce(${inferenceRun.tokenUsage}, json_object()),
            json_object(
              'promptTokens', coalesce(json_extract(${inferenceRun.tokenUsage}, '$.promptTokens'), 0) + ${promptTokens},
              'completionTokens', coalesce(json_extract(${inferenceRun.tokenUsage}, '$.completionTokens'), 0) + ${completionTokens},
              'totalTokens', coalesce(json_extract(${inferenceRun.tokenUsage}, '$.totalTokens'), 0) + ${totalTokens}
            )
          )
        `,
      })
      .where(eq(inferenceRun.id, id));
  }

  async getTurnsByInferenceRunId(inferenceRunId: string): Promise<InferenceRunTurn[]> {
    return this.db
      .select()
      .from(inferenceRunTurn)
      .where(eq(inferenceRunTurn.inferenceRunId, inferenceRunId))
      .orderBy(inferenceRunTurn.sequence);
  }

  async getByUser(
    userId: string,
    options: { limit: number; cursor?: string }
  ): Promise<PaginatedResult<InferenceRun>> {
    const cursorFilter = options.cursor
      ? sql`${inferenceRun.createdAt} < ${options.cursor}`
      : undefined;

    const rows = await this.db
      .select()
      .from(inferenceRun)
      .where(and(eq(inferenceRun.requestedByUserId, userId), cursorFilter))
      .orderBy(desc(inferenceRun.createdAt))
      .limit(options.limit);

    return paginateByCreatedAt(rows, options.limit);
  }
  
  // ... other methods
}
```

### Database Migration

Keep migrations DB-native SQL. Query and repository code should use Drizzle's SQL-like APIs, while migration files stay as explicit SQL for D1.

```sql
-- migrations/0024_create_inference_run.sql
CREATE TABLE inference_run (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  requested_by_user_id TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('workout_generation', 'program_generation', 'movement_analysis')),
  model_id TEXT NOT NULL,
  input TEXT NOT NULL, -- JSON
  output TEXT, -- JSON, nullable
  status TEXT NOT NULL CHECK (status IN ('pending', 'queued', 'processing', 'completed', 'failed', 'cancelled')),
  turn_count INTEGER NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  queued_at DATETIME,
  started_at DATETIME,
  completed_at DATETIME,
  token_usage TEXT, -- JSON {promptTokens, completionTokens, totalTokens}
  error TEXT, -- JSON {code, message, retryable}
  -- Note: Domain tables (workout, training_block, etc.) have inference_run_id FKs
  coordinator_id TEXT, -- Durable Object ID for Phase 3
  
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (requested_by_user_id) REFERENCES users(id)
);

CREATE INDEX idx_inference_run_tenant_status ON inference_run(tenant_id, status, created_at DESC);
-- Note: Create index on domain tables instead:
-- CREATE INDEX idx_workout_inference_run ON workout(inference_run_id);

-- migrations/0025_create_inference_run_turn.sql
CREATE TABLE inference_run_turn (
  id TEXT PRIMARY KEY,
  inference_run_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('system', 'user', 'assistant', 'tool')),
  content TEXT, -- nullable for assistant with only tool_calls
  tool_calls TEXT, -- JSON array of tool calls, only for assistant
  tool_call_id TEXT, -- References assistant's tool call, only for tool
  tool_name TEXT, -- Function name for tool responses
  token_usage TEXT, -- JSON for this specific turn
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  raw_response TEXT, -- JSON for debugging
  
  FOREIGN KEY (inference_run_id) REFERENCES inference_run(id) ON DELETE CASCADE
);

CREATE INDEX idx_inference_run_turn_run ON inference_run_turn(inference_run_id, sequence);
CREATE UNIQUE INDEX idx_inference_run_turn_sequence ON inference_run_turn(inference_run_id, sequence);
```

### Building the Message History

When calling the LLM, reconstruct the conversation from turns:

```ts
// packages/inference/src/messageBuilder.ts
export async function buildMessagesFromTurns(
  repo: InferenceRepository,
  inferenceRunId: string,
  systemPrompt?: string
): Promise<Array<{ role: string; content: string; name?: string; tool_call_id?: string; tool_calls?: unknown }>> {
  const turns = await repo.getTurnsByInferenceRunId(inferenceRunId);
  
  const messages: Array<{ role: string; content: string; name?: string; tool_call_id?: string; tool_calls?: unknown }> = [];
  
  // Add system prompt if provided and no system turn exists
  if (systemPrompt && !turns.some(t => t.role === 'system')) {
    messages.push({ role: 'system', content: systemPrompt });
  }
  
  for (const turn of turns.sort((a, b) => a.sequence - b.sequence)) {
    const msg: { role: string; content: string; name?: string; tool_call_id?: string; tool_calls?: unknown } = {
      role: turn.role,
      content: turn.content ?? '',
    };
    
    if (turn.role === 'assistant' && turn.toolCalls) {
      msg.tool_calls = turn.toolCalls;
    }
    
    if (turn.role === 'tool') {
      msg.tool_call_id = turn.toolCallId ?? '';
      msg.name = turn.toolName ?? '';
    }
    
    messages.push(msg);
  }
  
  return messages;
}
```

### Phase 1 Deliverables

- [x] `inference` package in apps/app with schemas, types, and repository interface
- [x] D1 migrations for `inference_run` and `inference_run_turn` tables
- [x] D1 implementation of `InferenceRepository`
- [x] Factory functions for creating inference runs per type
- [x] Message builder utility for reconstructing conversation history
- [x] cli to test the model `inference create`, `inference get <ID>`

---

## Phase 2: Queue-Based Async

Move LLM processing out of the request path using Cloudflare Queues. The TanStack server function creates the inference record (with initial turns) and enqueues a message; a separate queue worker consumes messages and performs the LLM call.

### Architecture

```
┌─────────────┐     POST /api/workouts/generate      ┌─────────────────┐
│   Client    │ ───────────────────────────────────▶ │  TanStack API   │
│             │                                      │    (Worker)     │
└─────────────┘◄─────────────────────────────────────└────────┬────────┘
       │                           │                          │
       │                    202 Accepted                      │
       │               { inferenceId, status }                │
       │                                                      │
       │ 1. Create inference_run (status: pending)            │
       │ 2. Add user turn (sequence: 0)                       │
       │ 3. Enqueue message with inferenceId                  │ enqueue
       │ 4. Update status: queued                             ▼
       │                                               ┌──────────────┐
       │                                               │   Queue      │
       │                                               │ (inference)  │
       │                                               └──────┬───────┘
       │                                                      │
       │                                               consume│
       │                                                      ▼
       │                                               ┌──────────────┐
       │                                               │ Queue Worker │
       │                                               │              │
       │                                               │ 1. Build msgs│
       │                                               │ 2. Add system│
       │                                               │ 3. LLM call  │
       │                                               │ 4. Add asst  │
       │                                               │    turn      │
       │                                               │ 5. Exec tools│
       │                                               │ 6. Add tool  │
       │                                               │    turns     │
       │                                               │ 7. Create    │
       │                                               │    Workout   │
       │                                               │ 8. Update:   │
       │                                               │    completed │
       └───────────────────────────────────────────────└──────────────┘
                                                           │
                                                           │ persist
                                                           ▼
                                                    ┌──────────────┐
                                                    │   Database   │
                                                    │              │
                                                    │ • inference  │
                                                    │ • turns      │
                                                    │ • workout    │
                                                    └──────────────┘
```

### Flow

1. **Client** sends `POST /api/workouts/generate` with generation parameters
2. **TanStack Server Function**:
   - Validates input with Zod
   - Creates `inference_run` record with `status: 'pending'`
   - Adds initial `user` turn with the request (sequence: 0)
   - Enqueues message to Cloudflare Queue containing `inferenceId`
   - Updates record to `status: 'queued'`
   - Returns `202 Accepted` with `{ inferenceId, status: "queued" }`
3. **Queue Worker** consumes message:
   - Fetches `inference_run` by ID
   - Builds message history from turns + adds system prompt
   - Updates status to `processing`, sets `startedAt`
   - Calls LLM via `runAiPipeline`
   - Adds `assistant` turn (sequence: 1) with response
   - If tool calls: executes tools, adds `tool` turns, loops back to LLM
   - Creates `Workout` entity from final result
   - Updates `inference_run` with `status: 'completed'`, output, `completedAt`
4. **Client** polls `GET /api/inference/$inferenceId` for status updates

### TanStack Server Function

```ts
// apps/app/src/server/workouts/generate.ts
import { createServerFn } from '@tanstack/react-start';
import { z } from 'zod';
import { WorkoutGenerationInput } from '@chalkmd/inference';

export const generateWorkout = createServerFn({ method: 'POST' })
  .validator(WorkoutGenerationInput)
  .handler(async ({ context, data }) => {
    const { env, user, tenant } = context;
    
    const inferenceRepo = createInferenceRepository(env.DB);
    
    // 1. Create inference run
    const inferenceRun = await inferenceRepo.create({
      tenantId: tenant.id,
      requestedByUserId: user.id,
      type: 'workout_generation',
      modelId: env.DEFAULT_WORKOUT_MODEL,
      input: data,
      output: null,
      status: 'pending',
      queuedAt: null,
      startedAt: null,
      completedAt: null,
      tokenUsage: null,
      error: null,
      coordinatorId: null,
    });
    
    // 2. Add user turn with the request
    await inferenceRepo.addTurn({
      inferenceRunId: inferenceRun.id,
      sequence: 0,
      role: 'user',
      content: JSON.stringify(data.parameters),
      toolCalls: null,
      toolCallId: null,
      toolName: null,
      tokenUsage: null,
      rawResponse: null,
    });
    
    // 3. Enqueue for processing
    await env.INFERENCE_QUEUE.send({
      inferenceId: inferenceRun.id,
      tenantId: tenant.id,
      type: 'workout_generation',
    }, {
      contentType: 'json',
    });
    
    // 4. Mark as queued
    await inferenceRepo.updateStatus(inferenceRun.id, 'queued', {
      queuedAt: new Date(),
    });
    
    // 5. Return accepted
    return {
      inferenceId: inferenceRun.id,
      status: 'queued' as const,
    };
  });
```

### Queue Worker with Tool Support

```ts
// apps/queue-worker/src/handlers/inference.ts
import { type MessageBatch } from '@cloudflare/workers-types';
import { runAiPipeline } from '@/infra/ai';

export interface InferenceMessage {
  inferenceId: string;
  tenantId: string;
  type: 'workout_generation' | 'program_generation' | 'movement_analysis';
}

export async function handleInferenceBatch(
  batch: MessageBatch<InferenceMessage>,
  env: WorkerEnv
): Promise<void> {
  const inferenceRepo = createInferenceRepository(env.DB);
  
  for (const message of batch.messages) {
    const { inferenceId, type } = message.body;
    
    try {
      // 1. Fetch and validate
      const run = await inferenceRepo.getByIdWithTurns(inferenceId);
      if (!run) {
        console.error(`Inference run not found: ${inferenceId}`);
        message.ack();
        continue;
      }
      
      // 2. Mark processing
      await inferenceRepo.updateStatus(inferenceId, 'processing', {
        startedAt: new Date(),
      });
      
      // 3. Process with tool loop
      const result = await processWithToolLoop(run, env, inferenceRepo);
      
      // 4. Mark completed with result
      await inferenceRepo.updateOutput(inferenceId, result.output);
      await inferenceRepo.updateStatus(inferenceId, 'completed', {
        completedAt: new Date(),
      });
      
      message.ack();
    } catch (error) {
      const isRetryable = isRetryableError(error);
      
      await inferenceRepo.updateError(inferenceId, {
        code: error.code || 'UNKNOWN',
        message: error.message,
        retryable: isRetryable,
      });
      
      if (!isRetryable || message.attempts > 3) {
        await inferenceRepo.updateStatus(inferenceId, 'failed');
        message.ack();
      } else {
        message.retry();
      }
    }
  }
}

async function processWithToolLoop(
  run: InferenceRun & { turns: InferenceRunTurn[] },
  env: WorkerEnv,
  repo: InferenceRepository
): Promise<{ output: Record<string, unknown>; entityId: string }> {
  // Build messages from existing turns
  let messages = await buildMessagesFromTurns(repo, run.id, getSystemPrompt(run.type));
  let sequence = run.turns.length;
  
  const MAX_ITERATIONS = 5;
  
  for (let i = 0; i < MAX_ITERATIONS; i++) {
    // Call LLM
    const result = await runAiPipeline({
      response_type: 'object',
      model: run.modelId,
      messages,
      tools: getToolsForType(run.type), // Tool definitions
      max_tokens: 4096,
      temperature: 0.7,
      runner: env.AI,
      logger: console,
    });
    
    const response = result.data as {
      content: string | null;
      tool_calls?: Array<{ id: string; function: { name: string; arguments: string } }>;
    };
    
    // Add assistant turn
    const assistantTurn = await repo.addTurn({
      inferenceRunId: run.id,
      sequence: sequence++,
      role: 'assistant',
      content: response.content,
      toolCalls: response.tool_calls?.map(tc => ({
        id: tc.id,
        type: 'function',
        function: {
          name: tc.function.name,
          arguments: tc.function.arguments,
        },
      })) ?? null,
      toolCallId: null,
      toolName: null,
      tokenUsage: result.usage,
      rawResponse: result.raw,
    });
    
    await repo.incrementTurnCount(run.id, result.usage);
    
    // If no tool calls, we're done
    if (!response.tool_calls || response.tool_calls.length === 0) {
      // Parse final output and create entity
      const output = parseOutput(run.type, response.content);
      const entityId = await createEntity(run, output, env);
      return { output, entityId };
    }
    
    // Execute tool calls and add tool turns
    for (const toolCall of response.tool_calls) {
      const toolResult = await executeTool(toolCall.function.name, toolCall.function.arguments);
      
      await repo.addTurn({
        inferenceRunId: run.id,
        sequence: sequence++,
        role: 'tool',
        content: JSON.stringify(toolResult),
        toolCalls: null,
        toolCallId: toolCall.id,
        toolName: toolCall.function.name,
        tokenUsage: null,
        rawResponse: null,
      });
    }
    
    // Rebuild messages for next iteration
    messages = await buildMessagesFromTurns(repo, run.id, getSystemPrompt(run.type));
  }
  
  throw new Error('Max tool iterations exceeded');
}
```

### Queue Configuration (Wrangler)

```toml
# apps/api/wrangler.toml (API worker - producer only)
[[queues.producers]]
binding = "INFERENCE_QUEUE"
queue = "inference-queue"

# apps/queue-worker/wrangler.toml (Queue worker - consumer)
[[queues.consumers]]
queue = "inference-queue"
max_batch_size = 10
max_batch_timeout = 30
max_retries = 3

# Durable Object for Phase 3
[[durable_objects.bindings]]
name = "INFERENCE_COORDINATOR_DO"
class_name = "InferenceCoordinator"
script_name = "apps/queue-worker"
```

### Phase 2 Deliverables

- [ ] Queue worker app with inference handler
- [ ] Tool execution framework
- [ ] TanStack server function for workout generation
- [ ] Polling endpoint for inference status
- [ ] Error handling and retry logic
- [ ] Integration with existing workout repository

---

## Phase 3: Durable Object Coordination + Streaming

Add Durable Objects to enable real-time streaming of generation progress from the queue worker back to the client.

### Architecture

```
┌─────────────┐     POST /api/workouts/generate      ┌─────────────────┐
│   Client    │ ───────────────────────────────────▶ │  TanStack API   │
│             │◀─────────────────────────────────────│    (Worker)     │
└──────┬──────┘     202 { inferenceId, streamUrl }   └────────┬────────┘
       │                                                      │
       │                                                      │ 1. Create DO
       │                                               ┌──────▼───────┐
       │                                               │  Inference   │
       │                                               │ Coordinator  │
       │                                               │     DO       │
       │                                               │              │
       │◀──────────────────────────────────────────────│  WebSocket   │
       │         events: turn, progress, complete      │  / SSE       │
       │                                               └──────┬───────┘
       │                                                      │
       │                                               ┌──────▼───────┐
       │                                               │   Queue      │
       │                                               │   Worker     │
       │                                               │              │
       └───────────────────────────────────────────────│  DO.fetch()  │
                                                       │  /event      │
                                                       └──────────────┘
```

### Updated Flow

1. **Client** sends `POST /api/workouts/generate`
2. **TanStack Server Function**:
   - Creates `inference_run` with `status: 'pending'`
   - Adds user turn
   - Creates DO instance: `env.INFERENCE_COORDINATOR_DO.newUniqueId()`
   - Stores `coordinatorId` on the inference run
   - Enqueues message with `inferenceId` and `coordinatorId`
   - Returns `202 Accepted` with `{ inferenceId, streamUrl: "/api/inference/:id/stream" }`
3. **Client** immediately connects to WebSocket/SSE endpoint
4. **Queue Worker**:
   - Consumes message, gets DO stub via `coordinatorId`
   - Posts turn creation events to DO as they happen
   - Streams tool execution progress
   - Posts final completion event
5. **DO** broadcasts all events to connected clients

### DO Event Types

```ts
type InferenceCoordinatorEvent =
  | { type: 'status'; status: InferenceStatus }
  | { type: 'turn_created'; turnId: string; sequence: number; role: string }
  | { type: 'tool_call'; name: string; arguments: string }
  | { type: 'tool_result'; name: string; durationMs: number }
  | { type: 'chunk'; content: string; turnId: string } // For streaming responses
  | { type: 'progress'; step: string; detail?: string }
  | { type: 'complete'; output: Record<string, unknown>; entityIds: string[]; turnCount: number }
  | { type: 'error'; code: string; message: string };
```

### Phase 3 Deliverables

- [ ] `InferenceCoordinator` Durable Object
- [ ] WebSocket and SSE support in DO
- [ ] Queue worker integration with DO event posting
- [ ] TanStack stream route
- [ ] React hook for consuming stream
- [ ] Fallback to polling if DO unavailable

---

## Migration Path

1. **Phase 1**: Deploy inference model and repository
2. **Phase 2**: Deploy queue worker, validate end-to-end with polling
3. **Phase 3**: Add DO behind feature flag, test streaming with cohort
4. **GA**: Enable streaming by default, keep polling as fallback

## Why Items Link to Inference

The foreign keys go from domain entities (workout, training_block) **to** `inference_run`, not the reverse.

### The Direction

```ts
// workout, training_block, etc.
interface Workout {
  id: string;
  ...
  inferenceRunId: string | null;  // Nullable: null = manually created
}

// inference_run has NO entity fields
interface InferenceRun {
  id: string;
  ...
  // No entityType, no entityId
}
```

### Why This Direction?

| Scenario | Items→Inference ✅ | Inference→Items ❌ |
|----------|-------------------|-------------------|
| **"Show AI-generated workouts"** | `WHERE inference_run_id IS NOT NULL` | Join + filter on entity_type |
| **"What created this workout?"** | `workout.inferenceRunId` direct access | Reverse lookup by entity_id |
| **One inference → many workouts** | All items have same FK | Polymorphic FK or join table |
| **Enrichment (analyze existing)** | Reference in `input.workoutId` | Need separate enrichment table |
| **Workout deleted** | Set `inferenceRunId = null` | Orphaned reference in inference |

### Handling Enrichment

For **enrichment** (analyzing/updating existing items), the target ID goes in `input`:

```ts
// Enriching an existing workout
await inferenceRepo.create({
  type: 'movement_analysis',
  input: {
    workoutId: 'workout_123',  // Reference here, not FK column
    analysisType: 'difficulty_scoring',
  }
});
```

The result goes in `inference_run.output`. No FK needed from inference to workout.

### Query Patterns

```ts
import { asc, eq } from 'drizzle-orm';

// Get workout with its AI history
const workoutWithInference = await db
  .select({
    workout,
    inferenceStatus: inferenceRun.status,
    generatedAt: inferenceRun.createdAt,
  })
  .from(workout)
  .leftJoin(inferenceRun, eq(inferenceRun.id, workout.inferenceRunId))
  .where(eq(workout.id, workoutId));

// Get all turns that created a workout
const workoutRow = await db
  .select({ inferenceRunId: workout.inferenceRunId })
  .from(workout)
  .where(eq(workout.id, workoutId))
  .limit(1);

const turns = workoutRow[0]?.inferenceRunId
  ? await db
      .select()
      .from(inferenceRunTurn)
      .where(eq(inferenceRunTurn.inferenceRunId, workoutRow[0].inferenceRunId))
      .orderBy(asc(inferenceRunTurn.sequence))
  : [];

// Get all items from one inference (supports 1:N generation)
const generatedWorkouts = await db
  .select()
  .from(workout)
  .where(eq(workout.inferenceRunId, inferenceId));
```

This gives clean 1:N support without polymorphic FKs, and enrichment doesn't complicate the schema.

## Open Questions

1. **DO Pricing**: Estimate WebSocket hours vs. polling DB load
2. **Reconnection**: Handle client reconnect with event replay (use DO storage)
3. **Cancellation**: Send cancel signal from client → DO → queue worker (via DO alarm?)
4. **Rate Limiting**: Per-user limits across queue and DO
5. **Monitoring**: Track inference latency, queue depth, turn counts, DO utilization

## Related Docs

- `references/runtime.ai.md` — AI call patterns and JSON output
- `references/runtime.streaming.md` — SSE and streaming response patterns
- `references/packages.effection.md` — Structured concurrency for async flows
- `references/runtime.config.md` — WorkerEnv validation and Cloudflare bindings
- `references/data.access.md` — Database access patterns for persistence
- `references/data.models.md` — Model conventions and shared primitives
