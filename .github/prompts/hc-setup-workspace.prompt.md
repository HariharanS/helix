---
name: hc-setup-workspace
description: Validate workspace inputs, run setup, onboard repos if needed, and report readiness
mode: agent
agent: hc-setup
tools: ['read', 'search/codebase']
---

Set up a workspace end-to-end. Validate the registry and workspace inputs, run the canonical workspace setup flow, onboard repos marked `needs-onboarding` or `partial`, refresh repo-state, and report readiness.

Treat CRG as first-class in `code_review_graph.mode: mcp`; use `mode: off` only as an explicit emergency fallback.

${input:workspace:Workspace id or path to workspaces/{name}/workspace.yml}
${input:repos_csv:Optional — comma-separated repo ids when creating the first workspace manifest}
