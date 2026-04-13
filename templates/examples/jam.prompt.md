---
# NOTE: This is a snapshot for illustration purposes. The live version is at .github/prompts/jam.prompt.md
name: jam
description: Start an interactive jam session to refine a feature idea into a clear intent
agent: jam
tools: ['read', 'search/codebase']
---

Start a jam session to refine the following feature idea. Challenge my thinking, ask probing questions one at a time, and help me arrive at a clear, unambiguous intent that can drive a PRD.

${input:feature_idea:Describe your feature idea}
