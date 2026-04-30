---
name: hc-label-session
description: Label the most recent Helix trace with correctness, rework, and notes
mode: ask
tools: ['read', 'edit', 'search/codebase']
---

Help the operator write a label file for the most recent captured Helix trace. The label schema lives at `helix/docs/label-schema.md` — defer to it on edge cases.

Steps:

1. From the meta-repo root, list `.helix/traces/*.jsonl`. Pick the most recently modified file. The session id is the filename without `.jsonl`.
2. If `<session-id>.label.yml` already exists alongside, read it and ask the operator whether to overwrite. If they decline, stop.
3. Read the trace's first record and last `subagent` record. Show the operator a one-line summary: workspace, workflow, phase, total subagents, total tokens. This grounds them.
4. Ask three questions, one at a time. Re-ask if the answer is out-of-enum:
   - `correctness`: `match | partial | wrong` — did the produced artifact match what you would have written?
   - `rework`: `none | minor | major` — how much did you redo after the session?
   - `notes`: free-form, single-line, may be blank — what went right or wrong?
5. Write `<repo-root>/.helix/traces/<session-id>.label.yml` with exactly these three keys, in this order, no others:

   ```yaml
   correctness: <answer>
   rework: <answer>
   notes: "<answer escaped to a single line>"
   ```

   Escape embedded quotes and collapse newlines into spaces in `notes` — the schema requires a single line.

${input:trace_id:Optional — specific session id to label instead of the most recent}
