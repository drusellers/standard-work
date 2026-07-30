# Route (URL) Strategy

This document catalogs the application's UI routes, their purpose, and how they map to the codebase. Use this when adding new screens or refactoring URL structure.

## Principles

- **RESTful when possible**: Use nouns for resources (`/workouts`, `/workouts/:id`), verbs for actions (`/login`, `/logout`).
- **Consistent hierarchy**: Nest related resources (`/workouts/:id`, `/workouts/:id/edit`).
- **Flat file structure**: Keep all route files in `src/routes/` with dot-notation (no nested folders).
- **Layout groups**: Use underscore prefix for layouts that don't affect URL (`_authenticated`).
- **User-facing URLs matter**: URLs are part of the UI—keep them readable and bookmarkable.

## Current Route Catalog

### App Routes (`apps/app`)

Authentication and user management:

| Route | File | Purpose | Auth |
|-------|------|---------|------|
| `/` | `_authenticated.index.tsx` | Dashboard/home for logged-in users | Required |
| `/login` | `login.tsx` | Email/password login form | Public |
| `/login/sso-callback` | `login.sso-callback.tsx` | OAuth provider callback | Public |
| `/signup` | `signup.tsx` | Account creation | Public |
| `/logout` | `logout.tsx` | Session termination | Required |

Workout management:

| Route | File | Purpose | Auth |
|-------|------|---------|------|
| `/workouts` | `_authenticated.workouts.index.tsx` | List user's workouts | Required |
| `/workouts/new` | `_authenticated.workouts.new.tsx` | Create new workout | Required |
| `/workouts/:workoutId` | `_authenticated.workouts.$workoutId.tsx` | View workout detail | Required |

System routes:

| Route | File | Purpose | Auth |
|-------|------|---------|------|
| `/robots.txt` | `robots[.]txt.ts` | SEO robots rules | Public |
| `/sitemap.xml` | `sitemap[.]xml.ts` | SEO sitemap | Public |

### Marketing Routes (`apps/marketing`)

| Route | File | Purpose | Auth |
|-------|------|---------|------|
| `/` | `index.tsx` | Marketing homepage | Public |
| `/posts` | `posts.index.tsx` | Blog post listing | Public |
| `/posts/:id` | `posts.$id.tsx` | Blog post detail | Public |
| `/_/unfurl` | `[_].unfurl.tsx` | Link preview generator | Public |

### Design System Routes (`apps/design`)

| Route | File | Purpose | Auth |
|-------|------|---------|------|
| `/` | `index.tsx` | Design system overview | Public |
| `/colors` | `colors.tsx` | Color token reference | Public |
| `/fonts` | `fonts.tsx` | Typography reference | Public |
| `/components` | `components.tsx` | Component showcase | Public |

## Route Patterns

### Layout Routes

Use underscore prefix for layout groups that wrap child routes without appearing in the URL:

```text
_authenticated.tsx              # Layout: checks auth, renders shell
_authenticated.index.tsx        # / (child of _authenticated layout)
_authenticated.workouts.tsx     # /workouts (parent for workout routes)
```

### Dynamic Parameters

Use dollar prefix for URL parameters:

```text
$workoutId  → /workouts/:workoutId
$id        → /posts/:id
```

### Nested Paths

Use dot notation for URL path separators:

```text
login.sso-callback.tsx    → /login/sso-callback
workouts.new.tsx          → /workouts/new
```

### Special Characters

Use brackets to escape literal characters that would otherwise have special meaning:

```text
robots[.]txt.ts          → /robots.txt (literal dot, not nested path)
[_].unfurl.tsx           → /_/unfurl (literal underscore prefix)
```

## Adding New Routes

1. **Decide the URL first**: What should users see in their address bar?
2. **Check this catalog**: Avoid collisions, maintain consistency.
3. **Map to filename**: Convert URL to dot-notation with appropriate escapes.
4. **Place in correct app**: App routes in `apps/app`, marketing in `apps/marketing`.
5. **Consider layout needs**: Should it be under `_authenticated`? Does it need its own layout?
6. **Update this doc**: Add the new route to the catalog table.

## Cross-Domain Routing

Two distinct hostnames serve different route sets:

- `hello.chalk.md` → Marketing app (`apps/marketing`)
- `chalk.md` → App (`apps/app`)

No routes should overlap between apps—each URL path belongs to exactly one app.
