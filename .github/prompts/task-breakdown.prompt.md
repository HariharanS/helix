---
name: task-breakdown
description: Break a technical design into small, independent tasks
agent: decomposer
mode: ask
tools: ['read', 'search/codebase']
---

Break down the technical design into small, independent, testable tasks with clear acceptance criteria. Each task should fit in a single agent context window.

${input:tech_design_path:Path to the tech-design file (e.g. tech-design.md)}
