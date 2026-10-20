# CSS / HTML

Some things that I've learned about designing CSS / HTML widgets.

### Components

* They should be built with the idea of taking up all the width possible
* Their width will instead be controlled by the external grid.

## Form Autocomplete

- **Admin screens:** default data-entry forms to `autocomplete="off"` so the operator's saved personal information does not populate customer or business records. Apply it to individual controls when they are outside a form, and avoid overriding it with autofill tokens on these fields.
- **Customer-facing screens:** use accurate semantic autocomplete tokens for fields that collect the customer's own information, such as `name`, `email`, `tel`, `shipping street-address`, and `billing postal-code`. Use distinct `section-*` prefixes for repeated groups. Do not rely on `autocomplete="on"` alone when a specific token applies.
- **Authentication:** use `username`, `current-password`, `new-password`, and `one-time-code` as appropriate, including on admin sign-in screens. Browsers and password managers may ignore `autocomplete="off"`; it is a preference, not a guarantee or security control.
- In React/JSX, the attribute is `autoComplete`. Shared form components must forward it to the native control.
- Verify representative admin and customer forms in supported browsers with saved autofill data available. Do not use fake field names or password tokens to defeat autofill.

```html
<!-- Admin: do not populate a customer's record with the operator's details. -->
<form autocomplete="off">
  <label>Customer email <input type="email" name="customerEmail" /></label>
</form>

<!-- Customer: help the customer enter their own information. -->
<form>
  <label>Email <input type="email" name="email" autocomplete="email" /></label>
  <label>Postal code <input name="postalCode" autocomplete="shipping postal-code" /></label>
</form>
```

## Screens

These are routable to, and should be the target of React Router

## The Layout/Chrome

### A sample layout

```text
<Layout>
    <Nav />
    <Stage><XxxScreen></Stage>
    // or
    <Stage screen={XxxScreen} />
</Layout> 
```

### A Dynamic Nav

```text
<Nav data={data} />

export function Nav(data) => {
  // check if mobile or non-mobile
  if (mobile) {
    <MobileNav {data} />
  } else {
    <ScreenNav {data} />
  }
}
```

Could include a dynamic layout possibly too to account for the sidebar vs hamburger menu. :thinking-face:

