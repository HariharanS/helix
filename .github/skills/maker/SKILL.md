---
name: maker
managed-by: helix-core
description: Creates new agents, skills, prompts, or workspaces from templates and conventions
argument-hint: "What to create (e.g. 'new skill for API scaffolding', 'new workspace for order-feature', 'new prompt for code review')"
user-invocable: true
disable-model-invocation: true
---

# Maker Skill

Creates new Helix artifacts (agents, skills, prompts, workspaces) following established conventions.

## What Maker Can Create

### 1. Agent

Creates a new `.github/agents/{name}.agent.md` with:

```yaml
---
name: {name}
description: {one-line description}
tools: [{appropriate tools}]
agents: [{agents it can spawn}]
user-invocable: {true|false}
disable-model-invocation: false
model: {model from tier assignment}
argument-hint: {what input it expects}
---
```

**Guidelines:**
- Choose model tier based on task type (reasoning/coding/analysis/visual/fast)
- Reference `.helix/model-config.yml` for tier assignments
- Write `model` as a single string, never an array
- Agent must be tech-agnostic — no stack-specific references
- Include "Read AGENTS.md and .instructions.md for conventions" directive
- Keep agent instructions lean — avoid long narrative guidance and generic advice
- Prefer markdown or YAML-shaped outputs over XML unless strict parsing is required
- Update `.helix/model-config.yml` assignments section
- Do NOT add `managed-by` — user-created agents are untagged by convention

### 2. Skill

Creates a new `.github/skills/{name}/SKILL.md` with:

```yaml
---
name: {name}
managed-by: helix-runtime
description: {one-line description}
argument-hint: {what input it expects}
user-invocable: true
disable-model-invocation: true
---
```

**Guidelines:**
- Skills should encode a repeatable workflow (not a one-off task)
- Include clear phases with expected inputs and outputs
- Include error handling guidance
- If created from a skill-synth candidate, reference the pattern examples
- Keep the skill short and operational — no filler or duplicated repo guidance

### 3. Prompt

Creates a new `.github/prompts/{name}.prompt.md` with:

```yaml
---
name: {name}
description: {one-line description}
mode: agent
agent: {target agent}
tools: [{appropriate tools}]
---
```

**Guidelines:**
- Prompts are for structured output generation (PRDs, designs, reports)
- Use `mode: agent` plus `agent:` for lifecycle prompts; use `mode: ask` and remove `agent:` only for guided operator Q&A
- Include a clear template in the body
- Prompts are simpler than skills — no multi-phase workflow
- Keep prompt bodies minimal and specific to the output you need

### 4. Workspace

Creates a new `workspaces/{name}/` directory with:

```
workspaces/{name}/
├── workspace.yml        # Participating repos and artifact entry paths
├── execution-plans/     # Machine-readable task contracts
├── task-boards/         # Empty, ready for use
└── decisions/           # Empty, ready for use
```

**Guidelines:**
- Ask for participating repo ids and workspace-specific roles
- Do not duplicate repo registry details from `helix-repos.yml` (instance-owned — created during installation from `helix/templates/helix-repos.yml.template`; `repos.yml` remains the legacy compatibility alias)
- Set status to "draft" or "active" as appropriate
- Suggest running workspace-sync after creation

## Workflow

1. Ask what to create (or parse from argument)
2. Determine the type (agent/skill/prompt/workspace)
3. Gather required information (name, purpose, model tier, tools)
4. Generate the artifact following the conventions above
5. Present for human review
6. Write the file after approval
