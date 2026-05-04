# Extensions Runtime And Context Management Future Plan

Date: 2026-05-04
Status: Future plan. Depends on `helix/docs/skill-projection-and-simplification-plan.md` landing first.

This plan sketches Helix's next runtime layer: a Copilot CLI extension named `hc-helix` that owns Helix's deterministic operations (resume, status, decisions, task advancement, CRG bridging, memory queries, context injection at session start). It is **not** a replacement for skills, agents, or `AGENTS.md`. Skills and agents remain the reasoning and procedure layers; the extension is the deterministic mutation and lookup layer.

This plan does not propose using extensions for skill routing. The simplification plan already solved skill discovery via projection. Building a router extension would re-introduce the complexity that projection eliminated.

## Goals

- Move Helix's deterministic operations from prose-in-skills to a Copilot CLI extension with structured tools.
- Make resume work from session boot via `onSessionStart` context injection.
- Provide structured tools for state mutation (decisions, task advancement, workspace switch).
- Wrap CRG as a tool with structured I/O instead of shell-out instructions in prose.
- Make distilled memory queryable so distillation pays off.
- Add deterministic checks at session boundaries (projection freshness, CRG availability, instruction-surface drift).

## Non-Goals

- Not a replacement for skills, agents, or `AGENTS.md`. Those remain.
- Not host-agnostic. The extension only runs on Copilot CLI. Helix-in-VSCode-chat or other agent harnesses are out of scope.
- Not a skill router. Skill discovery is solved by projection.
- Not a SQLite or database migration. Authored state stays as files.
- Not a new memory system. The extension queries existing `.helix/memory/` artifacts; it does not redesign the storage format.

## Pre-Requisites

This plan assumes the simplification plan has landed and is stable for at least one workspace cycle:

- All workspace skills are projected to the meta root.
- Skill router skill is removed; selection guidance lives in `AGENTS.md`.
- `resume.yml` is being written reliably on key events.
- Doctor diagnostics are in place and clean for typical workspaces.

If the simplification plan has not landed, **stop and land it first**. The extension's value depends on having clean deterministic state to query and mutate.

## Design Decisions

### Single Root Extension

- One extension named `hc-helix` lives at `meta-root/.github/extensions/hc-helix/extension.mjs`.
- All tools and hooks register from this single module. Internal modules under `tools/`, `hooks/`, and `lib/` keep code organized but only one `extension.mjs` calls `joinSession()` and registers.
- Rationale: Copilot CLI's hook registration is last-write-wins per hook type. Multiple Helix extensions registering `onUserPromptSubmitted` would silently lose hooks. One root extension that internally fans out avoids the footgun.

### Tool Namespace

- All tools registered by `hc-helix` MUST be prefixed `helix_*`.
- Tool names are globally unique across all extensions in a session; the `helix_` prefix reserves a namespace and avoids collisions with user-authored extensions.

### Bilingual Codebase

- Helix's existing deterministic logic is PowerShell (`Helix.Tools.psm1`, `setup-workspace.ps1`, `doctor.ps1`, `resolve-skill.ps1`).
- The extension is `.mjs` (Copilot CLI requirement; TypeScript not supported).
- Strategy: extension tools are thin wrappers that shell out to existing PowerShell scripts via `child_process` and parse structured output (preferably JSON; otherwise lines that the PowerShell script emits).
- Update the PowerShell scripts to emit JSON when invoked with a `-Json` flag. Do not rewrite their logic in JavaScript.

### Durable State On Disk

- The extension is stateless across `/clear`. Anything that must persist goes to `.helix/` files on disk.
- In-process state is allowed for session-scoped tracking (touched files, edit counts, retry contexts) and is explicitly scoped to one session.

### Safe Defaults For Hooks

- Hooks must never block forever. A failed hook should log and return without modifying the agent's flow.
- `stdout` is reserved for JSON-RPC. All extension logging goes to `stderr` or to a file under `.helix/logs/extensions/hc-helix.log`.

### Backward Compatibility

- The extension is additive. Existing agent and skill flows must continue to work even if the extension is not loaded (e.g. user has not opted in).
- Agents that benefit from extension tools should detect availability and degrade gracefully.

## Architecture

```
meta-root/
  .github/
    extensions/
      hc-helix/
        extension.mjs              # entry point, registers tools and hooks
        package.json               # type: module, no deps beyond @github/copilot-sdk (auto-resolved)
        tools/
          resume.mjs
          status.mjs
          decisions.mjs
          tasks.mjs
          crg.mjs
          memory.mjs
          grep.mjs
        hooks/
          on-session-start.mjs
          on-user-prompt-submitted.mjs
          on-post-tool-use.mjs
          on-session-end.mjs
        lib/
          pwsh.mjs                 # shells out to PowerShell, parses JSON
          paths.mjs                # meta-root, workspace paths
          log.mjs                  # stderr + file logging
```

## Tools

Each tool is registered with a JSON Schema for parameters. Return shape uses `{ textResultForLlm, resultType, structuredData? }` where supported.

### helix_resume

Description: Return the active workspace resume snapshot (L0–L3 as available).

Parameters:
```json
{
  "type": "object",
  "properties": {
    "workspace": { "type": "string", "description": "Workspace id; defaults to active" },
    "depth": { "type": "string", "enum": ["L0", "L1", "L2", "L3"], "default": "L1" }
  }
}
```

Behavior:
- L0: read `.helix/active-workspace.yml` and `workspaces/{id}/resume.yml`.
- L1: L0 + task board summary + last 3 decisions.
- L2: L1 + last session entry from `.helix/session-index.jsonl`.
- L3: L2 + top-3 distilled episodes (only if memory exists).

Return:
- `textResultForLlm`: human-readable summary.
- `structuredData`: parsed resume.yml plus the augmentations.

Replaces: `hc-resume.agent.md` reading 7 files manually.

### helix_status

Description: Lightweight current-state snapshot.

Parameters: none.

Behavior: returns active workspace id, current task id, blocked task ids, next action string, verification debt list. Sourced from `resume.yml`.

Return: `textResultForLlm` plus `structuredData`.

### helix_record_decision

Description: Append a decision to the workspace's decisions log.

Parameters:
```json
{
  "type": "object",
  "required": ["title", "body"],
  "properties": {
    "title": { "type": "string", "maxLength": 120 },
    "body": { "type": "string" },
    "context": { "type": "string", "description": "Optional: relevant task id, repo, or feature" }
  }
}
```

Behavior:
- Append to `workspaces/{id}/decisions.md` with timestamp, title, body, context.
- Update `resume.yml.updated_at`.

Return: decision id (timestamp-based slug) and absolute path.

### helix_advance_task

Description: Mutate the task board for a single task.

Parameters:
```json
{
  "type": "object",
  "required": ["task_id", "status"],
  "properties": {
    "task_id": { "type": "string" },
    "status": { "type": "string", "enum": ["todo", "in_progress", "blocked", "done"] },
    "notes": { "type": "string" }
  }
}
```

Behavior:
- Locate the task board for the active workspace's current feature.
- Update the task's status line and append notes.
- Update `resume.yml` (`current_task`, `last_completed_task`, `blocked_tasks`).

Return: updated task board path, new status.

### helix_crg_query

Description: Query the code-review-graph and return structured results.

Parameters:
```json
{
  "type": "object",
  "required": ["query"],
  "properties": {
    "query": { "type": "string" },
    "scope": { "type": "string", "description": "Optional: repo or workspace scope" },
    "mode": { "type": "string", "enum": ["mcp", "cli"], "default": "mcp" }
  }
}
```

Behavior:
- Shell out to the existing CRG client with structured output.
- If `mcp` mode fails, return a clear error with `resultType: "failure"` (do not silently fall back; the agent decides).

Return: structured CRG result; `textResultForLlm` summarizes top results.

Replaces: prose CRG instructions in setup and architect agents.

### helix_search_episodes

Description: Search distilled memory episodes by keyword/intent.

Parameters:
```json
{
  "type": "object",
  "required": ["query"],
  "properties": {
    "query": { "type": "string" },
    "k": { "type": "integer", "minimum": 1, "maximum": 20, "default": 5 }
  }
}
```

Behavior:
- Read `.helix/memory/episodes/*.md` and `.helix/memory/learnings/*.md`.
- Score by keyword match (initially) or embeddings (later); return top-k.
- Returns empty list with a friendly message if no memory exists.

Return: ranked list of episode paths plus excerpts.

This tool exists to **make distillation pay off**. Without a query interface, memory is dead weight; with one, the agent has a reason to consult it.

### helix_grep_workspace

Description: Grep across the active workspace's repos with deterministic scoping.

Parameters:
```json
{
  "type": "object",
  "required": ["pattern"],
  "properties": {
    "pattern": { "type": "string" },
    "repos": { "type": "array", "items": { "type": "string" }, "description": "Optional: subset of workspace repos" },
    "type": { "type": "string", "description": "Optional: file type filter" }
  }
}
```

Behavior:
- Resolve active workspace's repo paths.
- Run ripgrep across them (or fall back to grep) with reasonable defaults (case-insensitive, .gitignore-aware).
- Return matches with file path and line number.

Rationale: agents currently enumerate repos manually before grepping. A workspace-scoped grep removes that boilerplate.

## Hooks

### onSessionStart

Inject baseline context into every Helix session. This is the single biggest user-visible improvement.

Behavior:
1. Read `.helix/active-workspace.yml`. If absent, inject a one-line note ("No active Helix workspace; agent operates in default Copilot mode.") and return.
2. Read `workspaces/{id}/resume.yml`.
3. Run a projection freshness check (compare `index.yml` checksums to source repo skills); collect warnings.
4. Run a CRG availability ping; collect status.
5. Build a baseline-context message:
   - Active workspace id and current phase
   - Current task and next action
   - Blocked tasks (if any)
   - Last decision summary (last 1)
   - Projection freshness warnings (if any)
   - CRG status (only if degraded)
6. Inject as `additionalContext`.

Failure mode: if any of the above throws, log to stderr and inject a minimal context note. Never block the session.

### onUserPromptSubmitted

Detect resume-intent keywords and proactively augment the prompt.

Behavior:
- Match keywords: "resume", "where was I", "continue", "pick up where we left off".
- If matched, call the resume tool internally and prepend a structured snapshot to `additionalContext`.
- Never rewrite the user's prompt.

This is a quality-of-life hook, not a contract. Skip if it adds latency.

### onPostToolUse

Track Edit/Write side effects.

Behavior:
- For each `Edit` or `Write` tool call, record the touched path in a session-scoped set.
- On `helix_advance_task` or `helix_record_decision`, optionally annotate with the touched-files set as provenance.
- Detect projection drift: if a write hits a path under `.github/skills/` that has `projection.from_repo` in the index, log a warning and surface it to the agent on the next turn.

### onSessionEnd

Persist session metadata.

Behavior:
1. Append a record to `.helix/session-index.jsonl`:
   ```json
   { "session_id": "...", "workspace": "...", "started_at": "...", "ended_at": "...", "touched_files": [...], "tools_called": [...] }
   ```
2. If a touched-files set or decision-count threshold is met, append a distillation candidate to `.helix/memory/candidates.jsonl`. (Replaces the `distill-trigger.js` reminder hack with a deterministic event.)
3. Update `resume.yml.latest_sessions` (FIFO, keep last 5).

## Implementation Phases

The plan is intentionally phased so each phase delivers measurable value.

### Phase A: Skeleton + Resume Injection

Goal: prove the extension surface end to end with the highest-value capability.

Implement:
- `extension.mjs` skeleton with `joinSession()` and one tool (`helix_resume`) plus one hook (`onSessionStart`).
- `lib/pwsh.mjs` and `lib/paths.mjs`.
- Add `-Json` flag to existing PowerShell helpers that read `resume.yml` and `active-workspace.yml`.

Acceptance:
- Starting a session at the meta root emits an injected baseline context with active workspace and current task.
- Calling `helix_resume` returns the same data structured.
- `hc-resume.agent.md` is updated to optionally call `helix_resume` and fall back to file reads if unavailable.

Validation:
- Compare resume quality with and without the extension on the same workspace.
- Document the comparison in `helix/docs/extensions-runtime-future-plan.md` as an addendum.

Stop here for review. Decide whether to proceed.

### Phase B: State Mutation Tools

Implement: `helix_status`, `helix_record_decision`, `helix_advance_task`, `onPostToolUse` (touched-files tracking).

Update agents and skills:
- `hc-resume.agent.md`: prefer `helix_status` for quick checks.
- Decision-recording prose in any agent: link to the tool, deprecate prose instructions.
- Task-advancement prose in `hc-implementer.agent.md` and similar: link to the tool.

Acceptance:
- Agents that previously wrote to `decisions.md` and task boards via prose-driven file edits now call the tools.
- Existing manual file writes still work (additive).

### Phase C: CRG Tool

Implement: `helix_crg_query`.

Update agents and skills:
- Replace prose CRG instructions in `hc-architect.agent.md`, `hc-setup.agent.md`, and any skill that currently shells out to CRG via prose.
- Keep the hard gate: agent must not silently fall back when `mcp` mode fails (the tool returns `failure`, the agent decides).

Acceptance:
- CRG-using agents call the tool with structured input.
- No agent or skill contains prose `crg query ...` instructions after this phase.

### Phase D: Memory Search

Implement: `helix_search_episodes`, `onSessionEnd` distillation-candidate scheduling.

Re-evaluate distillation:
- Before this phase, distilled episodes existed but were not queryable. Distillation's value was theoretical.
- After this phase, agents can search episodes. Measure: do agents that have access to `helix_search_episodes` produce visibly better answers on tasks where memory is relevant?
- If yes, keep distillation. If no, consider deleting the distillation system entirely.

Acceptance:
- `helix_search_episodes` returns results from a workspace with seeded memory.
- Empty-memory case returns a friendly empty result.

### Phase E: Cleanup

Implement: `helix_grep_workspace`, additional hooks as needed.

Update prose surfaces:
- Reduce agents and skills that have been replaced by deterministic tools to thin role-only files.
- Run a bloat audit (carry over from the prior refactor plan Step 7) **with measurement**: count tokens-to-complete on a representative `hc-setup` flow before and after.

Acceptance:
- Each replaced agent/skill is shorter or links to the canonical owner.
- Bloat metric improved by a measurable margin (target: at least 20% fewer tokens for a representative flow). If not, the cleanup did not pay off and should be rolled back per file.

## Other Extension Scenarios Worth Considering

These are listed without commitment. Add to a phase if they prove valuable.

- **Projection freshness in onSessionStart** (already covered above).
- **Per-task scratchpad**: small `.helix/scratch/{task-id}.md` written via tool, persists across `/clear`. Use case: agents track exploratory notes that should not yet be promoted to decisions.
- **Test-on-edit hook**: `onPostToolUse` for code edits, runs the relevant test once, surfaces the result. Off by default, opt-in per workspace.
- **Drift-on-startup check**: `onSessionStart` runs `doctor.ps1 -Json` and surfaces critical warnings. Off by default for noise control.
- **Cross-workspace decision search**: `helix_search_decisions` over all workspaces' decisions logs. Useful when patterns span workspaces.

## Risks And Mitigations

- **Node-only and `.mjs` only.** Mitigation: shell-out to existing PowerShell rather than rewriting.
- **Hook collisions across extensions.** Mitigation: one root extension; document this in `helix/AGENTS.md` and the extension README.
- **Tool name collisions with user extensions.** Mitigation: `helix_*` prefix on every tool.
- **Host lock-in to Copilot CLI.** Mitigation: agents and skills remain host-agnostic; extension is additive. If Helix later targets another host, extension capability is rebuilt for that host while agents remain.
- **State reset on `/clear`.** Mitigation: durable state on disk; in-process state is session-scoped only.
- **`stdout` corruption from accidental console.log.** Mitigation: lint rule to block `console.log` in extension code; all logging via `lib/log.mjs` to stderr or file.
- **Performance: hooks fire on every session start.** Mitigation: cap `onSessionStart` work at a fixed budget (e.g. 200ms wall clock); skip CRG ping if it takes longer than 100ms; cache projection checksums in `.helix/cache/`.
- **Migration cost.** Mitigation: phases A–E are gated; stop after each phase if value is not demonstrated.

## Validation Strategy

For each phase:

- Add JS-based regression tests under `helix/evals/regression/extensions/` that spawn the extension as a child process and exercise tools via JSON-RPC. (The Copilot SDK exposes test harnesses; if it does not, mock the SDK surface.)
- Add docs/source tests asserting that prose instructions for replaced flows are removed.
- After each phase, run an end-to-end scenario manually (one cold session, one resume-after-clear) and document the trace in `helix/docs/extensions-runtime-evidence.md`.

## Suggested Agent Prompt

Use this prompt for an implementing agent, only after the simplification plan has landed:

```
Implement helix/docs/extensions-runtime-future-plan.md, Phase A only.

Constraints:
- The simplification plan must already be merged. Verify by checking that helix/docs/skill-projection-and-simplification-plan.md exists and that workspaces/{id}/resume.yml is present in at least one workspace.
- Build only the extension skeleton, helix_resume tool, and onSessionStart hook in this patch.
- The extension lives at meta-root/.github/extensions/hc-helix/extension.mjs.
- Do not add any other tool or hook in this phase.
- Do not modify agents or skills beyond updating hc-resume.agent.md to optionally use helix_resume with a graceful fallback.
- Use shell-out to existing PowerShell scripts via child_process; do not reimplement their logic in JavaScript.
- All logging to stderr or .helix/logs/extensions/hc-helix.log; never to stdout.
- Tool names must be prefixed helix_*.
- Add regression tests under helix/evals/regression/extensions/ that exercise helix_resume against a synthetic workspace.

Stop after Phase A and produce a comparison note between resume quality with and without the extension. Do not proceed to Phase B without explicit instruction.
```

## Open Questions

These should be resolved before Phase A, not during:

1. Does the Copilot SDK provide a test harness for extensions? If not, what is the test strategy — mock the SDK or run a real CLI in CI?
2. How is the extension distributed across user machines? It lives in the meta repo; do users pull it from there or is there a separate install path?
3. Does `onSessionStart` fire when the user runs `/clear`? If yes, the projection freshness check runs every clear; budget accordingly.
4. Are there scenarios where Helix sessions legitimately run from a non-meta-root CWD (e.g. inside a workspace repo's directory)? If yes, the extension must detect and either degrade or refuse to load.
5. What is the cost/value of moving CRG fully behind the tool vs. keeping prose for low-frequency operations? Decide before Phase C.
