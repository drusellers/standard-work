# CLI Usage

This document covers the repository CLI in `apps/cli`.

The previous app-local CLI in `apps/app/src/cli` has been removed. All commands now run from `apps/cli`.

## Run The CLI

From the repository root:

```bash
npm run cli -- <command> [options]
```

The CLI sends requests to `@chalkmd/app` so command execution happens in Worker runtime context.

## Setup

For commands that call app endpoints (for example `workout-generate-ai`), configure both sides of the shared token:

- Local shell token for CLI requests: `CHALKMD_CLI_TOKEN`
- App runtime secret checked by the endpoint: `CLI_SHARED_TOKEN`

Set `CLI_SHARED_TOKEN` per environment in `@chalkmd/app`:

- local: add `CLI_SHARED_TOKEN=...` to `apps/app/.dev.vars`
- stg: `wrangler secret put CLI_SHARED_TOKEN --env stg` (run from `apps/app`)
- prd: `wrangler secret put CLI_SHARED_TOKEN --env prd` (run from `apps/app`)

## Command Summary

| Command | Purpose | Typical Use |
| --- | --- | --- |
| `tokens <inputs...>` | Estimate token counts for files resolved from file paths or glob patterns. | `tokens "apps/app/src/**/*.ts" --top 20` |
| `workout-generate-ai <description>` | Generate and persist a workout by calling `@chalkmd/app` endpoint `/_/cli/workout-generate-ai`. | `workout-generate-ai "20 minute partner wod" --env stg --difficulty intermediate --json` |
| `help [command]` | Show general or command-specific help text. | `help workout-generate-ai` |

## Command Details

### `tokens`

Estimate token length for one or more files.

Options:

| Option | Description | Default |
| --- | --- | --- |
| `-e, --encoding <encoding>` | Tokenizer encoding (for example `cl100k_base`). | `cl100k_base` |
| `--json` | Print structured JSON output. | `false` |
| `--top <count>` | Show only the top N largest files by token count. | _unset_ |

Examples:

```bash
npm run cli -- tokens "apps/app/src/**/*.ts"
npm run cli -- tokens "apps/app/src/**/*" --top 15 --json
```

### `workout-generate-ai`

Generate and persist a workout through `@chalkmd/app`.

The command requires a shared CLI token that the app endpoint validates.

Required environment variables:

- `CHALKMD_CLI_TOKEN`

Environment target mapping:

| `--env` value | Target base URL |
| --- | --- |
| `local` | `http://localhost:3000` |
| `stg` | `https://staging.chalk.md` |
| `prd` | `https://chalk.md` |

Options:

| Option | Description | Default |
| --- | --- | --- |
| `--env <env>` | Target environment: `local`, `stg`, or `prd`. | `local` |
| `--base-url <url>` | Override resolved environment base URL. | _unset_ |
| `--target-duration <duration>` | Duration bucket: `short`, `medium`, `long`. | _unset_ (function default applies) |
| `--difficulty <level>` | Difficulty: `beginner`, `intermediate`, `advanced`, `rx`. | _unset_ (function default applies) |
| `--equipment <item>` | Equipment list; repeat option or pass comma-separated values. | `[]` |
| `--json` | Print server response as JSON. | `false` |

Examples:

```bash
CHALKMD_CLI_TOKEN=... \
npm run cli -- \
  workout-generate-ai "15 minute conditioning with kettlebell and bodyweight" \
  --env local \
  --target-duration medium \
  --difficulty intermediate \
  --equipment kettlebell \
  --equipment pull-up-bar

CHALKMD_CLI_TOKEN=... \
npm run cli -- \
  workout-generate-ai "long aerobic workout using rower and dumbbells" \
  --env stg \
  --equipment "rower,dumbbells" \
  --json
```
