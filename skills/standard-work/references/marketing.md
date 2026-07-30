# Marketing

## Direction

- The marketing site is intentionally simple while the product is early.
- We are selling software for fitness trainers (for example college strength coaches and personal trainers) to design and manage training programs.
- The platform includes an optional tool that connects to a remote LLM service to provide deeper training detail and planning support.
- Current layout direction is a single-column page with explicit sections:
  - title
  - nav (TBD)
  - main hero
  - three promises
  - footer

## Inspiration

- We are drawing product and UX ideas from the note-taking system Obsidian.
- We are not copying Obsidian's UI directly; we are borrowing the clarity and note-first thinking model.

## Implementation Notes

- Keep marketing-specific sections as local marketing components.
- Continue to align with the shared design-system contract in `references/design-system.md`.
- Keep SEO implementation and canonical rules in `references/marketing.seo.md`.

## Typography

- Fonts are loaded with Fontsource packages (not remote Google Fonts imports).
- Body copy uses `Open Sans Variable` across both apps.
- Marketing headings use `Outfit Variable`.
- App headings use `Outfit Variable`.
- Font families are applied through shared design-system tokens:
  - `--font-family-body`
  - `--font-family-heading`
- App-level font overrides are defined in app-local stylesheets:
  - `apps/marketing/src/styles/fonts.css`
  - `apps/app/src/styles/fonts.css`
