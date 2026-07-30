# Design System

This document defines the shared design system for ChalkMD across the monorepo.

## Goals

- One visual and interaction language across marketing and app surfaces.
- Centralized implementation in `@chalkmd/design-system`.
- Predictable theming and density through tokenized layers, not one-off component overrides.
- A style direction that blends web brutalism with minimal systems thinking.

## Stack

- **Tailwind CSS v4** for token-driven styling and CSS layer composition.
- **ShadCN (Base UI variant)** as the component baseline and accessibility foundation.
- **CSS variables** as the contract between design tokens, app context, and component behavior.

## Four-Layer Model

The system is organized into four explicit layers. Each layer can only depend on layers below it.

### 1) Primitives

Raw, brand-level tokens. No product meaning.

- Color values (e.g. white, black, neutral ramps, accent ramps), defined in **OKLCH** to keep perceptual steps consistent across light and dark themes.
- Typographic foundations (font families, scale, line-height, letter spacing).
- Spacing and sizing scales.
- Radius, border widths, shadows.
- Motion timing and easing primitives.

Examples:

- `--color-neutral-0` ... `--color-neutral-1000`
- `--space-1` ... `--space-12`
- `--radius-0`, `--radius-1`, `--radius-2`
- `--duration-fast`, `--duration-base`

Color guidance:

- Author primitive color tokens in OKLCH first; derive semantic/contextual mappings from those tokens.
- Avoid ad hoc hex/RGB values in component styles.
- Use contextual remapping (not one-off overrides) to tune contrast between light and dark modes.

### 2) Semantic

Intent-level tokens mapped from primitives. These express UI meaning.

- Surface/background/foreground roles.
- Border and separator roles.
- Interactive roles (primary, secondary, destructive, muted).
- Focus, selection, and feedback roles.
- Typography roles (body, heading, label, mono).

Examples:

- `--surface-0`, `--surface-1`, `--surface-2`, `--surface-3`
- `--text-on-surface-0`, `--text-on-surface-1`, `--text-on-surface-2`, `--text-on-surface-3`
- `--text-primary`, `--text-secondary`, `--text-inverse`
- `--border-default`, `--border-strong`
- `--action-primary-bg`, `--action-primary-fg`

Surface scale (current direction):

- Define four semantic surfaces: `--surface-0`, `--surface-1`, `--surface-2`, `--surface-3`.
- `--surface-0` is the page background.
- Higher surface numbers represent increased elevation/separation from the page plane.
- Use numeric surface tokens only (no descriptive alias tokens).
- Which components consume each surface level is a component-layer decision.

On-surface text guidance:

- Pair every surface token with a matching readable foreground token: `--text-on-surface-0` ... `--text-on-surface-3`.
- Container-like components (page, panels, cards, dialogs) should use matching surface + on-surface token pairs.
- Keep `--text-primary`/`--text-secondary` for global typography roles; use `--text-on-surface-*` when text is directly tied to a specific surface background.

Action token guidance (buttons and interactive controls):

- Buttons and controls should use action tokens, not surface tokens, for interactive fills and text.
- Define at least `--action-<intent>-bg`, `--action-<intent>-fg`, `--action-<intent>-border`, and `--action-<intent>-ring` (for example: `primary`, `secondary`, `destructive`, `ghost`).
- Use surface tokens for the surrounding container context, then action tokens for the control itself.
- Example pairing: a card on `--surface-1` can contain a primary button using `--action-primary-bg` + `--action-primary-fg`.

Token naming quick reference:

| Category | Pattern | Example tokens | Usage |
| --- | --- | --- | --- |
| Surface | `--surface-<level>` | `--surface-0`, `--surface-1`, `--surface-2`, `--surface-3` | Background planes by elevation; `--surface-0` is page background. |
| On-surface text | `--text-on-surface-<level>` | `--text-on-surface-0`, `--text-on-surface-1` | Foreground text paired directly to a surface level. |
| Global text | `--text-<role>` | `--text-primary`, `--text-secondary`, `--text-muted`, `--text-inverse` | General typography roles not tied to a specific surface. |
| Border | `--border-<role>` | `--border-default`, `--border-strong`, `--border-muted` | Separators, outlines, and container boundaries. |
| Action (per intent) | `--action-<intent>-<part>` | `--action-primary-bg`, `--action-primary-fg`, `--action-primary-border`, `--action-primary-ring` | Interactive controls like buttons, toggles, and selected states. |
| Focus | `--focus-<part>` | `--focus-ring`, `--focus-ring-offset` | Shared keyboard focus visibility and accessibility affordances. |

Intent list (initial):

- `primary`, `secondary`, `destructive`, `ghost`.

### 3) Contextual

Context-specific remapping of semantic tokens by mode.

- **Theme axis**: `light` vs `dark`
- **Density axis**: `comfortable` vs `compact`

Context is applied at the app root using data attributes:

- `data-theme="light" | "dark"`
- `data-density="comfortable" | "compact"`

This layer remaps semantic tokens and geometry tokens without changing component code.

Examples:

- `--control-height-sm`, `--control-height-md`, `--control-height-lg`
- `--layout-gap`, `--panel-padding`, `--field-padding-x`

### 4) Component

Concrete ShadCN components and product-specific UI built from semantic/contextual tokens.

- Components never hardcode primitive values.
- Variants map to semantic intent (e.g. `variant="primary"`, `variant="ghost"`).
- Density and theme behavior come from contextual tokens automatically.

## Visual Direction: Web Brutalism + Minimal

The default visual language should feel direct, legible, and opinionated.

- Strong contrast and visible structure.
- Crisp borders and clear separation over heavy gradients or glass effects.
- Sparse, intentional color usage; accents should signal meaning, not decoration.
- Bold typographic hierarchy with practical rhythm and generous readability.
- Motion should be functional and restrained.

Guidance:

- Prefer flat planes with sharp boundaries.
- Use spacing and alignment to create rhythm before adding ornament.
- Keep controls and feedback states obvious at a glance.

## Tailwind v4 Integration

Use Tailwind v4 in a CSS-first model:

- Keep tokens and shared layers in `packages/design-system/src/styles/`.
- Expose one shared stylesheet entry from `@chalkmd/design-system`.
- Let apps import shared styles, then add app-local styles only when needed.

Recommended structure:

- `tokens.css` for primitives and semantic contracts.
- `contexts.css` for `data-theme` and `data-density` remapping.
- `components.css` for shared component-level classes/utilities.
- `index.css` as the package entrypoint.

## ShadCN Integration

- Generate and maintain ShadCN components in `packages/design-system`.
- Standardize on the **Base UI** version/style of ShadCN components for all generated primitives.
- Wrap/extend base components to enforce ChalkMD token contracts.
- Keep component APIs stable and variant-driven.
- Prefer composition patterns over one-off forks per app.

Operational guidance:

- Use the ShadCN CLI as the intake path for new components, then normalize them to our token model before exposing them.
- Treat `components.json` as a reviewed configuration contract (aliases, style choices, and install targets) for consistent generation across the monorepo.
- Validate each newly added component against theme + density contexts before adoption.
- Prefer official ShadCN form patterns (`Field`, `Form`) with schema-first validation (Zod) for type-safe app forms.
- Track ShadCN upgrades against relevant docs areas: Tailwind v4, dark mode, monorepo guidance, and React version compatibility.

## Implementation Rules

- Components read only semantic/contextual tokens.
- Primitive usage is allowed only inside token definition files.
- New UI states must first define semantic token intent before component styling.
- Theme and density changes should not require component rewrites.
- Avoid ad hoc utility classes that bypass token contracts.

## Cross-App Defaults

- Marketing defaults to `data-density="comfortable"`.
- App defaults to `data-density="compact"`.
- Theme default can be app-specific, but both apps must support light and dark.

## Accessibility Baseline

- Maintain WCAG contrast targets in both light/dark modes.
- Preserve visible focus states on all interactive controls.
- Do not encode meaning with color alone.
- Support reduced motion preferences for non-essential transitions.

## Documentation + QA

- Storybook is owned by `packages/design-system` for token and component QA.
- Include stories that cover all key component variants across:
  - light + dark
  - comfortable + compact
- Add visual regression checks for critical components and states.
- Keep a lightweight ShadCN watchlist in design-system references/PR templates:
  - CLI + `components.json` changes
  - Tailwind v4 integration updates
  - Accessibility-affecting component updates (dialogs, menus, form controls)
  - Registry/MCP capabilities relevant to internal component distribution

## Adoption Sequence

1. Define primitives and semantic token contracts.
2. Implement contextual remapping for theme + density.
3. Migrate base ShadCN components to semantic tokens.
4. Roll out component variants and deprecate ad hoc styles.
5. Enforce via linting/review that primitives are not used directly in components.
