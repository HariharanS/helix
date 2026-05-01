# Helix Operator Workflows

Human-first map of how to use Helix today, what it should automate later, and how improvements discovered in an installed meta repo flow back into `helix-core`.

## Helix Today vs Target

| Topic | Supported today | Target direction |
|---|---|---|
| Entry surface | Small set of `@hc-*` agents, focused `/hc-*` skills, and optional VS Code prompt files | Same small surface regardless of host, with less host-specific trivia |
| Workspace knowledge | Repo AGENTS refresh works well; workspace AGENTS can be created during setup/onboard follow-on | `workspaces/{id}/AGENTS.md` synthesized automatically on refresh for multi-repo workspaces |
| Shared-pattern capture | Onboarding emits reusable-pattern tables; distiller appends candidate evidence | Onboarding/refresh persists workspace-level candidate evidence by default before synth review |
| Routing | Resolver exists, CRG is primary in many flows, manual search still leaks through in places | Skill-first dispatch, CRG-first retrieval, raw search last |
| Improvement rollout | Patch `helix-core`, then `sync-helix`, then rerun refresh/onboard in the installed meta repo | Same flow, with tighter migrations and more generated repair steps |

## Host Surfaces Today

| Host | Use first | Notes |
|---|---|---|
| Copilot CLI | `@hc-setup`, `@hc-helix`, `@hc-resume`, `@hc-distiller`, plus focused `/hc-*` skills | Custom repo `.prompt.md` files do **not** appear as slash commands today |
| VS Code chat | The same `@hc-*` agents, focused `/hc-*` skills, and `.github/prompts/*.prompt.md` | Prompt files are convenience wrappers, not the canonical source of behavior |

## Core Human Flows Supported Today

| Human goal | Copilot CLI surface | VS Code chat surface | Main outputs |
|---|---|---|---|
| Refresh workspace knowledge | `@hc-setup Set up/refresh workspace <id>...` | `@hc-setup ...` or `/hc-setup-workspace`, `/hc-refresh-workspace` | `.helix/repo-state/*.yml`, `.helix/repo-capabilities/*.yml`, `.helix/skills/index.yml`, repo AGENTS |
| Start or resume delivery | `@hc-helix`, `@hc-resume` | Same | PRD, tech design, task board, execution plan, implementation loop |
| Review shared patterns | `@hc-setup Review reusable-pattern candidates for workspace <id>` | Same or `/hc-review-reusable-patterns` | workspace-level shortlist, synth recommendation |
| Distill learnings | `@hc-distiller Distill the active workspace` | Same or `/hc-distill` | episodes, learnings, candidate evidence |
| Promote automation | `promote-skill.ps1` or `hc-maker` after synth approval | Same | projected `hr-*` skill or updated meta-root skill |
| Improve Helix itself | patch `helix-core`, then `.\helix\scripts\sync-helix.ps1` in installed meta repos | Same | updated managed runtime surface in each meta repo |

## What Helix Should Do Next

1. Treat `workspaces/{id}/AGENTS.md` as a standard refresh artifact for multi-repo workspaces.
2. Persist repeated onboarding `workspace-review` patterns into `.helix/skills/candidates/{id}.md` instead of leaving them inline-only.
3. Keep the skill registry/router internal to the runtime, not part of the human mental model.
4. Route work in this order where possible:
   - existing skill or projected skill
   - CRG-backed exploration
   - raw text search only for docs/config/infra gaps or explicit emergency fallback

## Control Plane vs Application Plane

| Plane | Lives where | Owns |
|---|---|---|
| Control plane | `helix-core` source repo | managed agents, skills, prompts, scripts, templates, docs |
| Application plane | installed meta repo | workspace manifests, generated state, repo-local candidate skills, workspace/platform knowledge |
| Delivery plane | attached product repos | product code, repo-specific AGENTS, repo-specific skills, tests, CI, infra |

## Improvement Feedback Loop

1. **Notice a gap** in a real meta repo session: missing workspace convention, wrong default, weak routing, bad generated guidance.
2. **Classify ownership** using [`helix-core-meta-repo-model.md`](./helix-core-meta-repo-model.md):
   - managed source file
   - template/default
   - script/generator behavior
   - instance-only state
3. **Patch `helix-core` first** when the behavior should become reusable.
4. **Roll it out** to installed meta repos with:

   ```powershell
   .\helix\scripts\sync-helix.ps1
   ```

5. **Regenerate instance-owned artifacts** by rerunning workspace refresh/onboard:

   ```text
   @hc-setup Refresh workspace <id>, rerun onboarding where needed, and report readiness.
   ```

6. **Review the new knowledge surfaces**:
   - `workspaces/{id}/AGENTS.md`
   - `.helix/skills/candidates/*.md`
   - `.helix/skills/index.yml`
7. **Only then** decide whether the gap was fully fixed or needs another upstream patch.

## Rule Of Thumb

- If the change should affect future installs or future syncs, patch `helix-core`.
- If the change is generated behavior, patch the script or workflow that emits it.
- If the change is only true for one meta repo or one workspace, keep it local.
