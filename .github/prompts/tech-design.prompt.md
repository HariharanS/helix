---
name: tech-design
description: Start a technical design session from a PRD
agent: architect
mode: ask
tools: ['read', 'search/codebase']
---

Create a technical design based on the PRD. Explore the relevant repos for existing patterns before designing. Use pseudo code for logic, mermaid for diagrams, and real code only for interface contracts.

${input:prd_path:Path to the PRD file (e.g. prd.md)}
