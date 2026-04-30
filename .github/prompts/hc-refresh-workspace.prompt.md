---
name: hc-refresh-workspace
description: Refresh an existing workspace after onboarding, repo changes, or branch switches
mode: agent
agent: hc-setup
tools: ['read', 'search/codebase']
---

Refresh the workspace. Re-run workspace setup, refresh repo-state and capability hints, verify CRG health, report any repos that still need onboarding, and suggest the next operator step.

${input:workspace:Optional — workspace id; leave blank to use the active workspace}
