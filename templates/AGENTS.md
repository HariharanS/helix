# templates AGENTS Guide

This directory contains templates for generated Helix artifacts.

## What Lives Here

- Artifact templates such as execution plans and context bundles
- Package-first artifact templates such as PRD and tech-design entry docs
- Meta-repo manifest templates such as `repos.yml`, `workspace.yml`, and `install-state.yml`
- Template examples
- Instruction and skill templates

## Read Order

1. Read [`../AGENTS.md`](../AGENTS.md) for repo-level rules
2. Open only the template for the artifact you are changing
3. Check `examples/` only when you need a concrete instance

## Editing Rules

- Keep templates compact and structurally consistent
- Bias toward progressive disclosure: summary or index first, detail second
- Prefer explicit fields over prose where downstream automation depends on them
- Do not bake feature-specific content into generic templates
- Do not keep stale stack-specific samples in canonical template paths; either refresh them in an isolated example area or delete them
