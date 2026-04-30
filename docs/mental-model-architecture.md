# Mental Model Architecture

`workspaces/{ws}/mental-model.md` is the workspace-scoped artifact that captures cross-repo coupling AI agents cannot crawl natively: shared terms, feature-flag inventory, calls/publishes/shares, behaviour conditions, optional state diagrams, and an append-only surprise log.

## Shape

Six sections, fixed order — see `helix/templates/mental-model.md.template`:

1. `## Domain Glossary`
2. `## Flag Inventory`
3. `## Coupling Map`
4. `## Behavior Conditions`
5. `## State Diagrams`
6. `## Surprise Log`

Each surprise log entry is a `### YYYY-MM-DD — {title}` subsection with `**Expected:** / **Actual:** / **Repos:**` lines. Append-only.

## Ownership

- **Architect** owns the document. Updates Domain Glossary / Flag Inventory / Coupling Map / Behavior Conditions / State Diagrams during the tech-design phase, alongside `tech-design/contracts.yaml` (T3).
- **Operator and implementer** append to the Surprise Log via `/hc-surprise`. The architect does not write directly to the log.
- No automatic firing — `/hc-surprise` is operator-invoked only. Surprises caught mid-implementation are recorded by the operator as they surface; the document is not auto-updated by hooks.

## Lifecycle

1. `setup-workspace.ps1` seeds the file from the template if absent (idempotent — re-runs do not overwrite).
2. Architect populates the upper sections during tech-design.
3. Operator and implementer use `/hc-surprise` to record divergences as they appear.
4. When a surprise is resolved structurally, the architect updates the relevant section above; the log entry stays as history.

## Deferred auto-population

Plan §7 originally called for static analysis at workspace setup to auto-populate Flag Inventory + Coupling Map. Useful detection requires knowing specific patterns (env-var conventions, appsettings.json, .env, framework-specific HTTP route or event-publish APIs) — that conflicts with Helix's hard tech-agnostic constraint.

Three paths were considered (see memory `project_helix_implementation_state.md` → `Notes for upcoming tracks`):

1. **Defer the static analyzer** *(taken)*. Ship the schema + ownership + capture loop. Operator fills in by hand; pain reveals what should auto-populate.
2. **Pluggable analyzer.** Operator supplies regex/glob patterns per stack in `.helix/mental-model-patterns.yml`. More general but adds config burden when nobody has asked for it.
3. **Hardcoded common patterns.** Detectors for env vars + appsettings.json + .env + standard HTTP route conventions. Violates tech-agnostic; bakes in stacks Helix doesn't otherwise know.

Path 1 was taken because the section names in the template are forward-compatible with whichever path lands later — the schema is the same regardless of who populates it.

## Open question

When should auto-population land, and via which path? Leave for the operator's first real surprise log to surface. The right signal is "the same kind of surprise has shown up three times in two workspaces" — at that point a detector pays for itself and the pattern is concrete enough to encode without inventing one.

## Example surprise entry

```markdown
### 2026-04-29 — orders-api emits OrderPlaced.v1 but orders-worker subscribes to v0

**Expected:** Coupling map said both repos handled v1.
**Actual:** orders-worker still hard-codes v0 in its subscription bootstrap.
**Repos:** orders-api, orders-worker
```
