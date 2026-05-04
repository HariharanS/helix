# Meta-Repo Skills Management

Helix projects every workspace repo's `.github/skills/*/SKILL.md` to the meta-root `.github/skills/` so that hosts (VS Code chat, Copilot CLI) can discover them from a single CWD. Projection is part of `setup-workspace.ps1`; it is automatic, deterministic, and replaces the older "candidate" model where repo skills were merely indexed but not host-visible.

## Design Rule

Every workspace skill is host-visible from meta-root through projection. The source-of-truth is the source repo; meta-root projections are read-only mirrors that carry provenance frontmatter.

This keeps the meta-repo as the orchestration root without forcing hosts to descend into nested `.github/skills` folders inside product repos.

## Skill Lifecycle

| State | Location | Meaning |
|---|---|---|
| Authored | `workspaces/{id}/repos/{repo}/.github/skills/{name}/SKILL.md` | Source-of-truth in the source repo |
| Projected | `.github/skills/{repo-short}-{skill-name}/SKILL.md` | Read-only mirror at meta-root, written by `setup-workspace.ps1`, carries `projection:` provenance frontmatter |
| Indexed | `.helix/skills/index.yml` | Projection ledger: every meta-root entry, with provenance and checksum |
| Promoted | `.github/skills/hc-{skill-name}/SKILL.md` in Helix core | The skill is stable enough to ship with Helix |
| Retired | `.helix/skills/graveyard/{skill-id}.yml` | The pattern is stale, unsafe, or too bespoke |
| Skipped | source frontmatter `projection: never` | Repo-local-only skill (e.g. relies on a specific repo's filesystem layout); not projected |

## Naming Policy

Use prefixes to identify ownership:

- `hc-*`: Helix core skills shipped by the Helix source repo. Live at meta-root, not projected.
- `hr-*`: Helix-reusable skills (legacy mechanism). Live at meta-root, treated as projected.
- `{repo-short}-{skill-name}`: workspace skills projected from active workspace repos. The folder *and* the frontmatter `name:` field are rewritten to this prefixed form so any host that keys off either will resolve unambiguously. The original name is preserved in `projection.from_name`.

`{repo-short}` is derived by slugifying `repo_id` from `helix-repos.yml` (lowercase, non-alphanumerics collapsed to `-`). Two repos whose ids slug to the same short name will fail projection with a hard collision error pointing at both source paths — disambiguate by renaming a repo id or marking one source skill `projection: never`.

## Choosing A Skill

Because every workspace skill is projected to meta-root, hosts can list and invoke them directly. There is no longer a runtime "router skill" that decides which skill to load — selection is the agent's job, guided by the descriptions in each `SKILL.md`, the `.helix/skills/index.yml` ledger, and the patterns documented in `helix/AGENTS.md` ("Choosing a skill"). See [`skill-projection-and-simplification-plan.md`](./skill-projection-and-simplification-plan.md) for the rationale.

The deterministic resolver remains as a developer/CI utility for verifying projection correctness:

```powershell
./helix/scripts/resolve-skill.ps1 -RepoId <repo-id> -Path <path> -Task "<task>"
```

To promote a projected workspace skill into a stable Helix-reusable `hr-*` skill:

```powershell
./helix/scripts/promote-skill.ps1 -SkillId <projected-name>
```

## Projection Rules

Project only skills that are useful from the meta-root orchestration loop.

A skill can be projected when:

- it is reusable across more than one task or phase;
- it is safe for autonomous or semi-autonomous agent use;
- it has clear scope and verification guidance;
- it does not leak private repo details into unrelated work;
- it remains short enough for the skill surface.

Do not project:

- one-off feature notes;
- broad architecture docs;
- domain glossaries better suited to workspace context;
- skills that require a human decision before every use;
- duplicate skills that only restate root or nested `AGENTS.md`.

## Index Shape

`install-helix.ps1` seeds core entries and `setup-workspace.ps1` rewrites the index after projecting the active workspace's skills. The index is now a projection ledger keyed off on-disk meta-root state — the writer scans `.github/skills/` and emits one entry per folder, picking up provenance from the projected SKILL.md frontmatter:

```yaml
schema_version: 2
updated_at: 2026-05-04T00:00:00Z
active_workspace: directdebit
skills:
  - id: hc-workspace-sync
    name: hc-workspace-sync
    status: core
    access:
      source: meta-root-skill
    origin:
      kind: helix-core
      source_path: .github/skills/hc-workspace-sync/SKILL.md
    path: .github/skills/hc-workspace-sync/SKILL.md
    requires_skill_use_record: true
  - id: rapid-api-paymentrequest-payment-contract-fixtures
    name: rapid-api-paymentrequest-payment-contract-fixtures
    status: projected
    access:
      source: projected
    origin:
      kind: workspace-projected
      source_path: .github/skills/rapid-api-paymentrequest-payment-contract-fixtures/SKILL.md
    path: .github/skills/rapid-api-paymentrequest-payment-contract-fixtures/SKILL.md
    projection:
      from_repo: rapid-api-paymentrequest
      from_path: .github/skills/payment-contract-fixtures
      from_name: payment-contract-fixtures
      projected_at: 2026-05-04T10:30:00Z
      checksum: sha256:abc...
    scope:
      repos:
        - rapid-api-paymentrequest
      paths: []
    requires_skill_use_record: true
```

`Read-HelixSkillIndex` upgrades v1 indexes to v2 in memory, stripping the deprecated `routing.use_mode` and `access.host_visible` fields. `Write-HelixSkillIndex` always emits v2.

Keep the index machine-readable. Human summaries can live in `workspaces/{id}/skill-catalog.md` if needed.

## Eval Requirements

Yes, this needs eval coverage. The router is only useful if Helix can prove it selects and loads the expected skill source.

Current deterministic regression tests cover:

- Index generation includes repo-local candidate skills with origin metadata.
- Resolver prefers projected `hr-*` skills over repo-local candidates.
- Resolver falls back to repo-local candidates when no projected skill exists.
- Resolver returns `needs_disambiguation` for equal matches.
- Projection creates an `hr-*` skill folder and updates the registry.

Remaining projection tests:

- Projection does not overwrite `hc-*` Helix core skills.
- Duplicate candidate names are not projected silently.

Then add a lightweight behavioral eval:

- Given a task touching `Rapid.Api.PaymentRequest` and an index entry for payment contract fixtures, the router output names that skill and references its source path.
- Given no matching projected skill, the router falls back to the repo-local skill source.
- Given conflicting skills, the router asks for disambiguation or uses the narrower scoped match.

## Implementation Plan

1. Done: add `hc-skill-router` as a Helix core skill. (Removed in the projection-and-simplification plan; selection guidance now lives in `helix/AGENTS.md` under "Choosing a skill".)
2. Done: write `.helix/skills/index.yml` during install and workspace setup.
3. Done: add deterministic resolver and regression coverage for routing/fallback/disambiguation.
4. Done: add `promote-skill.ps1` to project approved candidates into `.github/skills/hr-*`.
5. Next: extend onboard so repo-local skills are explicitly described as candidates, not assumed globally available.
6. Next: add model-facing behavior evals for Helix specialist and delegated general agents.

Until projection lands, agents should treat repo-local skills as useful files to read, not guaranteed invokable skills.
