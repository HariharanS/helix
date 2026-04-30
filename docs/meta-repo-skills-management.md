# Meta-Repo Skills Management

Helix discovers repo-specific skills during onboarding, but host support for invoking skills from nested product repos is not guaranteed across VS Code, Copilot CLI, and future runtimes. Treat repo-local skills as discovery artifacts until Helix indexes or projects them into the meta-repo runtime surface.

## Design Rule

Repo-local skills are discovery artifacts. Meta-root skills are runtime affordances.

This keeps the meta-repo as the orchestration root without pretending every nested `.github/skills` folder is automatically invokable from every host.

## Skill Lifecycle

| State | Location | Meaning |
|---|---|---|
| Discovered | `workspaces/{id}/repos/{repo}/.github/skills/{name}/SKILL.md` | Onboard found a recurring repo pattern |
| Candidate | `.helix/skills/index.yml` | Helix indexed the repo-local skill and recorded origin, scope, confidence, and safety notes |
| Indexed | `.helix/skills/index.yml` | Workspace sync can route agents to the skill source |
| Projected | `.github/skills/hr-{skill-name}/SKILL.md` | The skill is available from the meta-root runtime surface |
| Promoted | `.github/skills/he-{skill-name}/SKILL.md` in Helix core | The skill is stable enough to ship with Helix |
| Retired | `.helix/skills/graveyard/{skill-id}.yml` | The pattern is stale, unsafe, or too bespoke |

## Naming Policy

Use prefixes to identify ownership:

- `he-*`: Helix core managed skills shipped by the Helix source repo.
- `hr-*`: Helix runtime created or projected skills in an installed meta repo.

Do not put the repo id in the projected skill name by default. Store origin metadata in the index instead:

```yaml
id: hr-payment-contract-fixtures
origin:
  workspace_id: directdebit
  repo_id: Rapid.Api.PaymentRequest
  source_path: workspaces/directdebit/repos/Rapid.Api.PaymentRequest/.github/skills/payment-contract-fixtures/SKILL.md
scope:
  repos:
    - Rapid.Api.PaymentRequest
status: projected
```

If two repos discover incompatible skills with the same name, do not auto-project both. Either keep them as repo-local candidates or project with a scoped name such as `hr-paymentrequest-contract-fixtures`.

## Router Skill

The meta root contains a small Helix core router skill:

```text
.github/skills/he-skill-router/SKILL.md
```

The router does not magically force the host to load nested skills. Its job is to make the agent consult Helix's skill index and then read the right repo-local or projected skill file before acting.

Router behavior:

1. Resolve the active workspace from `.helix/active-workspace.yml`.
2. Read `.helix/skills/index.yml`.
3. Match the current task to repo, file paths, language, domain, and available skill scopes.
4. Prefer projected `hr-*` skills when available.
5. If no projected skill exists, read the indexed repo-local skill source directly.
6. Emit a `skill_use` record before acting.

This makes routing dependable even when a host does not expose nested repo skills as invokable commands.

When available, use the deterministic resolver:

```powershell
./helix/scripts/resolve-skill.ps1 -RepoId <repo-id> -Path <path> -Task "<task>"
```

To project an approved candidate into the meta-root runtime surface:

```powershell
./helix/scripts/promote-skill.ps1 -SkillId hr-payment-contract-fixtures
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

`install-helix.ps1` seeds core entries and `setup-workspace.ps1` refreshes workspace repo candidates in `.helix/skills/index.yml`:

```yaml
schema_version: 1
updated_at: 2026-04-30T00:00:00Z
active_workspace: directdebit
skills:
  - id: he-workspace-sync
    name: workspace-sync
    status: core
    origin:
      kind: helix-core
      source_path: .github/skills/workspace-sync/SKILL.md
    path: .github/skills/workspace-sync/SKILL.md
    projected_path: null
    scope:
      repos: []
      paths: []
    confidence: high
    requires_skill_use_record: true
  - id: hr-payment-contract-fixtures
    name: payment-contract-fixtures
    status: candidate
    origin:
      kind: repo-local
      workspace_id: directdebit
      repo_id: Rapid.Api.PaymentRequest
      source_path: workspaces/directdebit/repos/Rapid.Api.PaymentRequest/.github/skills/payment-contract-fixtures/SKILL.md
    path: workspaces/directdebit/repos/Rapid.Api.PaymentRequest/.github/skills/payment-contract-fixtures/SKILL.md
    projected_path: null
    scope:
      repos:
        - Rapid.Api.PaymentRequest
      paths: []
    confidence: medium
    requires_skill_use_record: true
```

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

- Projection does not overwrite `he-*` Helix core skills.
- Duplicate candidate names are not projected silently.

Then add a lightweight behavioral eval:

- Given a task touching `Rapid.Api.PaymentRequest` and an index entry for payment contract fixtures, the router output names that skill and references its source path.
- Given no matching projected skill, the router falls back to the repo-local skill source.
- Given conflicting skills, the router asks for disambiguation or uses the narrower scoped match.

## Implementation Plan

1. Done: add `he-skill-router` as a Helix core skill.
2. Done: write `.helix/skills/index.yml` during install and workspace setup.
3. Done: add deterministic resolver and regression coverage for routing/fallback/disambiguation.
4. Done: add `promote-skill.ps1` to project approved candidates into `.github/skills/hr-*`.
5. Next: extend onboard so repo-local skills are explicitly described as candidates, not assumed globally available.
6. Next: add model-facing behavior evals for Helix specialist and delegated general agents.

Until projection lands, agents should treat repo-local skills as useful files to read, not guaranteed invokable skills.
