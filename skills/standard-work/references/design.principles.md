# UI Design Principles

This document defines practical UI layout principles for building responsive, content-driven interfaces.

## Table of Contents

- [Prefer Content-Driven Layout Over Fixed Width](#prefer-content-driven-layout-over-fixed-width)
- [Design Checklist](#design-checklist)

## Prefer Content-Driven Layout Over Fixed Width

- Do not use fixed widths for primary page, section, or shell layout.
- Let content and viewport constraints shape layout behavior.
- Prefer Flexbox and CSS Grid for structure, flow, and reflow.
- Use fixed width only when the component is intrinsically sized and the fixed dimension is intentional.

Preferred for layout:

- Flex containers for directional flow and adaptive spacing.
- Grid containers for multi-column composition, balanced tracks, and explicit placement.
- Constraint-based sizing with `minmax()`, `clamp()`, and `max-width` where needed for readability.

Use fixed width only when it serves a clear component need, such as:

- Avatar, icon, badge, or chip sizing.
- Compact controls with deliberate affordance dimensions.
- Known media frames where aspect and frame size are part of the design intent.

Avoid:

```css
.page {
  width: 1200px;
}

.sidebar {
  width: 320px;
}
```

Prefer:

```css
.page {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(16rem, 24rem);
  gap: 1rem;
}

.content {
  min-width: 0;
}
```

## Design Checklist

- Is this a layout container? If yes, avoid fixed width by default.
- Can Flexbox or Grid express the same intent more adaptively? If yes, use them.
- Is width being constrained for readability (`max-width`) rather than hard-locking layout?
- Is a fixed width being used only for an intrinsically sized component?
- Does the layout still work cleanly across desktop and mobile breakpoints?
