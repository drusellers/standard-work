# Standard Work

Reusable standard work for coding agents, packaged as an Agent Skills / Pi package.

In Lean operations, "standard work" is the documented best-known way to perform a task. This repo applies that idea to Dru's software engineering preferences: code style, architecture, runtime behavior, data access, testing, platform choices, and related implementation guidance.

The package is intentionally lazy-loaded: the agent sees only the skill name and description until a task matches, then reads `SKILL.md`, then reads only the relevant files under `references/`.

## Install in Pi

From GitHub:

```sh
pi install git:github.com/drusellers/standard-work
```

Or from a local checkout while iterating:

```sh
pi install /Users/drusellers/dev/drusellers/standard-work
```

For one-off local runs without installing:

```sh
pi --skill /Users/drusellers/dev/drusellers/standard-work/skills
```

## Use with `rig`

Once installed with `pi install`, `rig` should pick the package up from Pi settings.

If you want `rig` to load a local checkout explicitly, add this skill path to the rig launch command:

```sh
--skill "$HOME/dev/drusellers/standard-work/skills"
```

## Repository Layout

```text
standard-work/
  package.json
  skills/
    standard-work/
      SKILL.md              # small trigger + lazy-loading workflow
      references/           # detailed Markdown standards
      scripts/search        # narrow reference search helper
```

## Maintenance

- Keep `SKILL.md` short. It is the first file loaded when the skill activates.
- Put detailed guidance in `skills/standard-work/references/`.
- Update `skills/standard-work/references/index.md` whenever references are added, renamed, or removed.
- Prefer many focused files over one giant file so agents can load only what they need.
