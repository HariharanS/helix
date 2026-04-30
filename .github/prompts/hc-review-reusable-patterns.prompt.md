---
name: hc-review-reusable-patterns
description: Review reusable-pattern candidates from onboarding or distill and route them through skill synth when appropriate
mode: agent
agent: hc-setup
tools: ['read', 'search/codebase']
---

Review reusable-pattern candidates for the active or specified workspace. Read onboarding reusable-pattern tables and any `.helix/skills/candidates/` evidence. If the evidence is strong enough, run `/hc-skill-synth` and present the resulting recommendation.

Do not project or create skills automatically. Stop at human review with the exact next step.

${input:scope:Optional — 'workspace', repo path, or candidate id}
