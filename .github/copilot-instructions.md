# Helix — Global Conventions

This workspace uses the Helix multi-agent development system.

## Architecture
- Serverless-first on AWS (Lambda, DynamoDB, S3, EventBridge, Step Functions)
- .NET 8/10 runtime
- SAM templates for infrastructure as code
- Azure DevOps CI/CD pipelines
- Multi-repo architecture — each service has its own repo

## Development Workflow
- Follow the Helix phase workflow: JAM → PRD → TECH DESIGN → TASK BREAKDOWN → IMPLEMENTATION → REVIEW → DISTILL
- Use task boards (`task-boards/`) to track progress
- Use decisions logs (`decisions/`) to record significant decisions
- Use memory system for learnings across sessions

## Code Principles
- Domain logic separated from infrastructure
- DynamoDB single-table design
- Pragmatic TDD — meaningful tests, not exhaustive
- Follow each repo's existing coding style — do not impose patterns from other repos
- Keep implementations minimal — do what the task requires, nothing more

## Agent Context
- Read AGENTS.md at repo root for service overview and conventions
- Read src/AGENTS.md for code-level patterns
- Read .copilot/repo-profile.md for structural overview
- Follow .instructions.md files for file-type-specific conventions
