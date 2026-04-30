---
name: hc-tech-design
description: Start a technical design session from a PRD
agent: hc-architect
mode: agent
tools: ['read', 'search/codebase']
---

Create a technical design based on the PRD. Reuse any existing context bundles, or have `@hc-architect` route research through `@hc-explorer` + `/hc-curate-context` so CRG is the primary retrieval engine before designing. Use pseudo code for logic, mermaid for diagrams, and real code only for interface contracts.

For small work, a single-file design is fine. For cross-repo or larger work, prefer a package-first design with `tech-design/index.md` plus focused subdocuments such as `contracts.md`, `domain-model.md`, and `execution-flow.md`.

${input:prd_path:Path to the PRD entry document (e.g. prd.md or prd/index.md)}
