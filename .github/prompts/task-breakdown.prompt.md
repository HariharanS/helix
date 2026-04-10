---
name: task-breakdown
description: Break a technical design into small, independent tasks
agent: decomposer
mode: ask
tools: ['read', 'search/codebase']
---

Break down the technical design into small, independent, testable tasks with clear acceptance criteria. Each task should fit in a single agent context window.

Produce both:
- a human-readable task board
- a machine-readable execution plan with commands, ownership boundaries, context bundle references, dependencies, and done criteria

Keep the task board concise. Put execution detail in the YAML execution plan, not in prose.

Only mark tasks as safe for autopilot or parallel fleet execution when the execution contract is explicit and conflict-free.

If the design is packaged, start from `tech-design/index.md` and reference the exact subdocuments each task depends on.

${input:tech_design_path:Path to the tech-design entry document (e.g. tech-design.md or tech-design/index.md)}
