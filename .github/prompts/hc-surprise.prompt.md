---
name: hc-surprise
description: Append a surprise to the active workspace's mental-model surprise log
mode: ask
tools: ['read', 'edit']
---

Help the operator record a cross-repo surprise — a moment where the mental model said one thing and reality showed another. The mental-model file lives at `workspaces/{active}/mental-model.md`; its shape is in `helix/templates/mental-model.md.template`.

Steps:

1. Read `.helix/active-workspace.yml`. If no workspace is active, ask the operator to set one with `/workspace-activate` and stop.
2. Resolve `workspaces/{active}/mental-model.md`. If it does not exist, copy `helix/templates/mental-model.md.template` to that path before continuing.
3. Ask three questions, one at a time:
   - `title`: one-line summary of the surprise
   - `expected`: what the mental model implied would happen
   - `actual`: what actually happened
   - Optional: `repos`: comma-separated repo ids involved
4. Append a new subsection under the existing `## Surprise Log` heading, after any existing entries, in this exact shape:

   ```markdown
   ### {YYYY-MM-DD} — {title}

   **Expected:** {expected}
   **Actual:** {actual}
   **Repos:** {repos}            # omit this line if repos was blank
   ```

   Use today's date in `YYYY-MM-DD`. Do not modify any other section, do not rewrite earlier surprise entries, and do not collapse blank lines elsewhere in the file.
