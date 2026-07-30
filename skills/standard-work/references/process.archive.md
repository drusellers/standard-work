# Change Log / Archive Process

**Purpose:** Document significant architectural decisions and changes for future reference.  
**Note:** This process will become an OpenCode command.

## When to Create a Changelog Entry

Create an entry when:
- Making irreversible architectural decisions
- Changing data models or domain boundaries
- Introducing new paradigms or patterns
- You want to capture "what was I thinking"

Don't create an entry for:
- Bug fixes
- Minor refactors
- Implementation details (use git history)
- Routine feature additions

## Format

### Filename Convention
```
YYYY-MM-DD-[brief-description].md
```

Examples:
- `2025-03-25-workout-system-migration.md`
- `2025-04-10-auth-provider-change.md`
- `2025-05-01-database-sharding.md`

### Required Header

```markdown
# YYYY-MM-DD: [Brief Title]

**Status:** Completed | In Progress | Superseded  
**Scope:** [One-line description of what changed]  
**Review for Deletion:** YYYY-MM-DD (3 months from creation)
```

### Required Sections

#### The Problem
What was wrong or missing? Why couldn't we continue with the current approach?

#### The Solution  
What did we change? Keep this high-level - no implementation details.

#### Key Decisions
List 3-5 major decisions with trade-offs explained. Focus on "why X instead of Y".

#### What This Enables
What capabilities or improvements does this change unlock?

### Optional Sections

#### Domain Model
Include ASCII diagrams or ERDs when discussing data model changes.

#### Migration Notes
If there was a migration, note the migration filenames.

## Retention Policy

Entries are kept for **3 months** from the date in the filename.

**Review Process:**
1. On the review date, read the entry
2. Ask: "Did I reference this in the past 3 months?"
3. If no: Delete it (git history preserves the full details)
4. If yes: Keep it and set a new review date 6 months out

**Why 3 months?**
- Long enough to have needed it if it was valuable
- Short enough to not accumulate clutter
- Most "why did we do this?" questions happen within weeks, not months

## Example Entry

Use the required header and sections above as the canonical example. If a consuming project keeps a local changelog, store concrete examples there instead of adding project-specific history to this shared standards package.

## Future: OpenCode Integration

This process will become an OpenCode command:

```
/archive-change [description]
```

Which will:
1. Prompt for required information
2. Create the file with proper naming
3. Set the review date
4. Optionally add to git

## Location

For consuming projects, keep changelog entries in a local `docs/changelog/` directory or another project-specific archive directory.

The local changelog directory should include a `README.md` that explains this retention policy to future developers.
