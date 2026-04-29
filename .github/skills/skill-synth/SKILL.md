---
name: skill-synth
managed-by: helix-core
description: Scans codebase for repeating patterns, evaluates skill-worthiness, and produces candidate skill reports for the maker skill to create
argument-hint: "Repo path to scan (e.g. '../service-a') or 'workspace' to scan all repos"
user-invocable: true
disable-model-invocation: true
---

# Skill Synth

Scans a codebase for repeating patterns and evaluates whether they should become reusable skills.

## Two-Pass Synthesis

Run in two model tiers (per `.helix/model-config.yml`) so cheap scanning doesn't pay reasoning-model cost and final judgment doesn't get rushed:

- **Pass 1 — `fast` tier (Haiku).** Phases 1–2 (Scan, Evaluate). Identify and shortlist candidates. Cheap, broad. Output: a raw candidate list with frequency + consistency scores.
- **Pass 2 — `reasoning` tier (Opus).** Phases 3–5 (Prove Reusability, Report, Handoff). Held-out replay, parameter extraction, recommendation. Expensive, careful. Output: the candidate report.

Always run both passes. A pass-1 candidate that pass-2 downgrades to `NOT WORTH IT` is the system working — the cheap scan is allowed to be generous.

## Workflow

### 1. Scan

Search the target repo(s) for structural repetition:

- **File-level patterns:** Groups of files that always appear together (e.g., handler + test + config for each endpoint)
- **Code-level patterns:** Boilerplate blocks that repeat across files (e.g., error handling wrappers, DI registration, response formatting)
- **Workflow-level patterns:** Multi-step sequences that developers repeat (e.g., "add migration → update model → update tests → update docs")
- **Config-level patterns:** Repeated configuration blocks (e.g., IaC resource definitions, CI pipeline stages)

### 2. Evaluate

For each candidate, score against these criteria:

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Frequency | High | How often does this pattern appear? (>3 times = worth considering) |
| Consistency | High | Is the pattern always the same, or does it vary? (High consistency = good skill candidate) |
| Complexity | Medium | How many steps or files involved? (Simple patterns may not be worth a skill) |
| Error-prone | Medium | Do developers often get this wrong? (Check git log for fix commits) |
| Automatable | High | Can an agent produce this reliably from a template + parameters? |

### 3. Prove Reusability

For each promising candidate, do NOT stop at frequency. Validate that it can become a stable skill:

1. **Variation analysis**
   - Compare at least 3 occurrences
   - Separate fixed boilerplate from true parameters
   - Record where the pattern varies and why
2. **Parameter extraction**
   - Define the smallest set of inputs needed to reproduce the pattern
   - Reject the candidate if too much of the output is bespoke or context-heavy
3. **Held-out replay**
   - Pick at least one occurrence that was NOT used to derive the template
   - Test whether the proposed parameters + workflow could recreate it accurately
   - If replay fails, downgrade or reject the candidate

### 4. Report

Produce a candidate report:

```markdown
# Skill Synthesis Report: {repo or workspace}
**Scanned:** {date}
**Patterns found:** {N}
**Candidates recommended:** {M}

## Candidates

### 1. {Pattern Name}
- **Type:** file-level | code-level | workflow-level | config-level
- **Frequency:** {N} occurrences
- **Consistency:** HIGH | MEDIUM | LOW
- **Complexity:** {description}
- **Error history:** {any fix commits related to this pattern}
- **Example:** {one concrete example from the codebase}
- **Parameters:** {true variable inputs needed to drive the pattern}
- **Fixed boilerplate:** {what stays constant across occurrences}
- **Variation notes:** {where the pattern diverges across examples}
- **Held-out replay:** PASS | PARTIAL | FAIL
- **Recommendation:** CREATE SKILL | ADD TO EXISTING | NOT WORTH IT
- **Skill parameters:** {what inputs would the skill need}

## Rejected Patterns
- {Pattern}: {why it's not worth a skill}
```

### 5. Handoff to Maker

For each candidate marked "CREATE SKILL", the report provides enough context for the `maker` skill to generate the actual SKILL.md file.

## Scanning Strategies

- **For file patterns:** Group files by naming convention (e.g., `*Handler.*`, `*Test.*`, `*Config.*`), look for co-occurrence
- **For code patterns:** Search for similar import blocks, similar function signatures, repeated AST shapes
- **For workflow patterns:** Analyze git log for files that are always committed together
- **For config patterns:** Diff similar config files to find the template vs. the parameters

## Guidelines

- Only recommend skills for patterns with 3+ occurrences
- A skill should save more time than it costs to maintain
- Prefer fewer, higher-quality skills over many trivial ones
- Check if the pattern is already covered by an existing skill before recommending a new one
- Repo-specific skills go in the repo; cross-cutting skills go in Helix
- Do NOT recommend `CREATE SKILL` unless held-out replay passes or is very close with clearly bounded gaps
- Reject candidates whose true parameter list is too large or whose variation is driven by business-specific logic
