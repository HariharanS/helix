# Copilot Pet Webview Prototype

Tiny static prototype for a Copilot CLI webview pet. It is intentionally just
`content/` assets so the folder can be copied into a future
`.github/extensions/copilot-pet/content/` webview extension.

Suggested webview size:

```js
const webview = new CopilotWebview({
  extensionName: "copilot_pet",
  contentDir: join(import.meta.dirname, "content"),
  title: "Loopi",
  width: 228,
  height: 320,
});
```

For the production pet, remove the bottom state-picker buttons and the window can
be shorter. The buttons are only for previewing states without Copilot events.

Prototype states:

- `idle`
- `thinking`
- `tool`
- `pass`
- `fail`

The future extension should push state changes from Copilot events into the
page with `copilot_pet_eval`, for example:

```js
window.setPetState("tool", "Running tests");
```

Open `content/index.html` directly in a browser to preview the small animated
surface without installing extension dependencies.
