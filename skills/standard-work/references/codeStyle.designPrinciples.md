# Design Principles

This document defines cross-language design principles for API ergonomics, safer defaults, and dependency composition.

## Table of Contents

- [Instantiate Values To Avoid Null Pointer Paths](#instantiate-values-to-avoid-null-pointer-paths)
- [Prefer Discriminated Unions For Variant States](#prefer-discriminated-unions-for-variant-states)
- [Push Null and Undefined Handling To Boundaries](#push-null-and-undefined-handling-to-boundaries)
- [Compose Dependencies Through Factories and Injection](#compose-dependencies-through-factories-and-injection)
- [Follow the Hollywood Principle](#follow-the-hollywood-principle)
- [Extract Cohesive Parts From Large Modules](#extract-cohesive-parts-from-large-modules)
- [Practical Defaults](#practical-defaults)
- [When Nullable Values Are Correct](#when-nullable-values-are-correct)
- [Design Checklist](#design-checklist)

## Instantiate Values To Avoid Null Pointer Paths

- Whenever possible, return an instantiated, usable value instead of `null` or `undefined`.
- Stable return shapes reduce null reference exceptions and remove repetitive caller checks.
- A caller should usually be able to use the result directly without defensive branching.

## Prefer Discriminated Unions For Variant States

- When a value can be in multiple meaningful states, model those states explicitly with discriminated unions (or the closest language-native equivalent).
- This makes impossible states harder to represent and expected branches easier to handle.
- Prefer explicit variants over nullable fields that force ambiguous checks.

Example shape:

```text
Result =
  | { kind: "ready", value: Data }
  | { kind: "empty" }
  | { kind: "error", reason: ErrorInfo }
```

## Push Null and Undefined Handling To Boundaries

- Normalize nullable or missing values as close as possible to the source of absence.
- Apply defaults at boundaries such as network adapters, repository mappers, queue handlers, and third-party integration layers.
- Do not spread `??` and presence checks across every consumer when boundary code can normalize once.

Goal:

```text
source with nullable data -> boundary normalization/defaulting -> stable internal API
```

## Compose Dependencies Through Factories and Injection

- Inject dependencies into business workflows instead of constructing them ad hoc inside use cases.
- Prefer factory-based creation for complex dependencies so setup, configuration, and lifecycle concerns are centralized.
- Use ecosystem-idiomatic tools, but keep the architecture intent consistent across languages.

Many teams hand-wire dependencies in a top-level composition root instead of using a DI framework.

- .NET and Java often use DI containers/frameworks.
- JavaScript and TypeScript often use explicit factory functions and object composition.
- Rust projects commonly hand-wire dependencies because explicit ownership and lifetimes can make generic container-based DI harder to apply cleanly.

The key rule is not the framework choice. The key rule is dependency injection and explicit composition.

Preferred flow:

```text
config/env -> factories/composition root -> top-level app context -> services/use cases
```

The top-level context object should hold the assembled collaborators needed by boundaries and domain workflows.

## Follow the Hollywood Principle

- Prefer "don't call us, we'll call you" interactions at module and object boundaries.
- Avoid call chains where a consumer asks for internal state, inspects that state, then decides which internal method to call next.
- Expose intent-level operations (for example `run()`, `sync()`, `publish()`) and keep branching decisions inside the owning module.

Avoid this shape:

```text
consumer -> getState() -> inspect state -> choose method -> call method
```

Prefer this shape:

```text
consumer -> doTheThing() -> module decides and executes internally
```

This reduces chatty APIs, hides representation details, and keeps decision logic close to the data and behavior it depends on.

Example:

```text
Avoid:

syncPlan = syncService.readPlan(input)

if syncPlan.shouldFullSync:
  syncService.runFullSync(syncPlan)
else:
  syncService.runDeltaSync(syncPlan)

Prefer:

syncService.sync(input)

# syncService decides full vs delta internally
```

## Extract Cohesive Parts From Large Modules

- When a class or function grows very large, it often contains a smaller abstraction that should be extracted.
- A practical heuristic is around 500 lines, but the real signal is cohesion, not an exact number.
- If a member field is only used by a subset of methods, that subset is often a separate responsibility.

Common extraction signals:

- One member variable appears in only a small method cluster.
- Several private helpers exist only to support one sub-flow.
- Naming becomes broad because the module now owns multiple concerns.

Example:

```text
Avoid:

class ReportService {
  userRepo
  billingRepo
  pdfEngine   # used only by 4/20 methods

  # ... many unrelated methods
}

Prefer:

class ReportService {
  userRepo
  billingRepo
  pdfRenderer
}

class PdfReportRenderer {
  pdfEngine
  # methods for PDF-specific rendering
}
```

This keeps parent modules smaller, improves testability, and makes ownership boundaries easier to understand.

## Practical Defaults

- Collections: default to empty collections (`[]`, `{}`) when empty has valid meaning.
- Counts and totals: default to `0` when unknown is not a distinct business state.
- Flags: default to explicit booleans when semantics are clear.
- Strings: default only when an empty string is domain-safe and not misleading.

## When Nullable Values Are Correct

- Keep `null` or `undefined` when absence has real semantic meaning.
- Examples: unknown vs known-empty, not requested, not permitted, intentionally unset.
- Do not hide business meaning by inventing a default that changes interpretation.

## Design Checklist

- Can a consumer proceed safely with a default value? If yes, return an instantiated default.
- Does absence carry domain meaning? If yes, keep it explicit as a nullable/optional value or variant state.
- Can boundary code normalize once for all callers? If yes, move defaulting there.
- Are variant outcomes explicit and exhaustive? If not, prefer a discriminated union model.
- Are dependencies injected instead of being created ad hoc inside business logic?
- Are complex dependencies created through factories or explicit composition wiring?
- Is dependency wiring centralized in a top-level context/composition root?
- Does the API expose intent-level operations instead of requiring state inspection + follow-up calls?
- Is decision logic kept inside the owning module when possible?
- Is this module large because it contains multiple responsibilities that can be extracted?
- Is there a field/method cluster that can become its own class or module?
