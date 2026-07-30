# CLI Interface Catalog

This page captures the current command surface for `chalkmd` in `apps/cli`.

## Purpose

- Provide a system-level view of available CLI interfaces.
- Show command type (local utility vs HTTP-backed query/mutation).
- Map commands to server routes for quick impact analysis.

## Source of Truth

- CLI entrypoint: `apps/cli/src/index.ts`
- Command implementations: `apps/cli/src/commands/`
- CLI HTTP routes in app: `apps/app/src/routes/[_].cli.inference.ts`, `apps/app/src/routes/[_].cli.workout-generate-ai.ts`

## Command Catalog

| Type | Command | Purpose | Transport | Auth |
|---|---|---|---|---|
| Local Utility | `chalkmd tokens <inputs...>` | Estimate token counts for files/globs | In-process (no HTTP) | None |
| API Mutation | `chalkmd workout-generate-ai <description>` | Generate and persist a workout | HTTP `POST` | CLI bearer token |
| API Mutation | `chalkmd inference create` | Create a generic inference run; optional first user turn | HTTP `POST` | CLI bearer token |
| API Mutation | `chalkmd inference run-next <inferenceId>` | Run one LLM step from saved turns and persist assistant output | HTTP `POST` | CLI bearer token |
| API Query | `chalkmd inference get <id>` | Read inference state and optional turn history | HTTP `GET` | CLI bearer token |

## Command Groups

| Group | Subcommands | Notes |
|---|---|---|
| `tokens` | none | Local analysis command; supports `--encoding`, `--top`, `--json`. |
| `workout-generate-ai` | none | Focused legacy workflow for direct workout generation. |
| `inference` | `create`, `run-next`, `get` | Generic inference test workflow for run + next-step execution. |


## Operational Notes

- Environments: `--env local|stg|prd` defaults to `local`.
- Base URL override: `--base-url <url>` is available on HTTP-backed commands.
- Token: HTTP-backed commands require `CHALKMD_CLI_TOKEN`.

## Planned Companion Catalogs

- Event/interface catalogs may be added later if a consuming project needs them.
