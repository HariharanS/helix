# HC/HR Runtime Surface Rename Plan

## Decision

Use `hc-*` for Helix Core managed runtime artifacts and `hr-*` for Helix Runtime generated or projected artifacts.

- `hc-*`: shipped from the Helix source repo and copied into installed meta repos by install/sync.
- `hr-*`: created, indexed, or projected inside an installed meta repo by Helix runtime workflows.
- Repo-local candidate skills inside product repos remain unprefixed until indexed or projected.

No backward compatibility is required. New installations should expose only the clean HC/HR naming model.

## Target Shape

Core agents:

```text
.github/agents/hc-helix.agent.md
.github/agents/hc-setup.agent.md
.github/agents/hc-planner.agent.md
.github/agents/hc-implementer.agent.md
```

Core skills:

```text
.github/skills/hc-workspace-sync/SKILL.md
.github/skills/hc-onboard/SKILL.md
.github/skills/hc-tdd-cycle/SKILL.md
.github/skills/hc-skill-router/SKILL.md
```

Runtime projected skills:

```text
.github/skills/hr-payment-contract-fixtures/SKILL.md
```

Core prompts:

```text
.github/prompts/hc-jam.prompt.md
.github/prompts/hc-tech-design.prompt.md
.github/prompts/hc-task-breakdown.prompt.md
.github/prompts/hc-distill.prompt.md
```

Every core agent, prompt, and skill frontmatter `name:` must match its physical filename or folder base name.

## Registry Rules

`.helix/skills/index.yml` must use:

- `hc-*` for Helix Core entries.
- `hr-*` for runtime projected entries and indexed repo-local candidate IDs.

Example:

```yaml
skills:
  - id: hc-workspace-sync
    status: core
    origin:
      kind: helix-core
      source_path: .github/skills/hc-workspace-sync/SKILL.md

  - id: hr-payment-contract-fixtures
    status: candidate
    origin:
      kind: repo-local
      source_path: workspaces/directdebit/repos/Rapid.Api.PaymentRequest/.github/skills/payment-contract-fixtures/SKILL.md
```

## Implementation Checklist

- Rename `.github/agents/*.agent.md` to `hc-*.agent.md`.
- Rename `.github/skills/*` Helix Core folders to `hc-*`.
- Rename `.github/prompts/*.prompt.md` to `hc-*.prompt.md`.
- Update frontmatter `name:` values.
- Update `agents:` arrays and `handoffs.agent` values.
- Update prompt `agent:` values.
- Update operator examples to `@hc-*` and `/hc-*`.
- Update skill registry logic in `scripts/Helix.Tools.psm1`.
- Keep `scripts/promote-skill.ps1` projecting only `hr-*`.
- Update installer, templates, docs, and regression tests.
- Add or keep a naming convention regression test for the HC/HR runtime surface.

## Validation

Run:

```powershell
$files = 'scripts\Helix.Tools.psm1','scripts\setup-workspace.ps1','scripts\install-helix.ps1','scripts\init-meta-repo.ps1','scripts\doctor.ps1','scripts\resolve-skill.ps1','scripts\promote-skill.ps1'
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { $errors | ForEach-Object { "${file}:$($_.Message)" }; exit 1 }
}
```

Run:

```powershell
node --test evals\regression\*.test.js
git diff --check
```

Run a stale-reference gate over tracked Helix source files:

```powershell
Get-ChildItem -Path .github,docs,templates,scripts,evals,workspaces,.helix -Recurse -Force -File |
  Select-String -Pattern '(?<![A-Za-z0-9])h[e]-[a-z0-9]|@(architect|decomposer|distiller|explorer|helix|implementer|jam|planner|resume|reviewer|scribe|setup|tdd-red|ui-tester)\b|(?<![A-Za-z0-9._-])/(workspace-sync|onboard|surprise|build-graph|curate-context|maker|review-delta|review-pr|skill-synth|task-board|tdd-cycle|vertical-slice-verifier|distill|jam|label-session|skill-audit|skill-graveyard|task-breakdown|tech-design)(?![A-Za-z0-9._/-])'
```

Expected:

- Core runtime files are physically `hc-*`.
- Runtime projected skills remain `hr-*`.
- Product repo candidate skill folders remain unprefixed until projected.
- No unprefixed core agent invocations or command references remain.
