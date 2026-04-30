# Running and Debugging Playwright Tests

## Always run via the task-contract command

Test runner commands are language- and repo-specific. **Read them from the task contract** (`commands.focused_test`, `commands.full_suite`) — never hardcode `npx playwright test`. The contract knows whether the repo uses npm scripts, `dotnet test`, `pytest`, Maven, or a custom wrapper.

Examples of what the contract may resolve to (illustrative, not prescriptive):

```bash
# TypeScript repos
PLAYWRIGHT_HTML_OPEN=never npx playwright test
PLAYWRIGHT_HTML_OPEN=never npm run e2e

# C# / .NET repos
dotnet test tests/E2E.Tests
dotnet test --filter "FullyQualifiedName~LoginTests"

# Python repos
pytest tests/e2e
pytest tests/e2e/test_login.py

# Java / Maven
mvn test -Dtest=LoginTest
```

To suppress the auto-opening HTML report in TS/JS, set `PLAYWRIGHT_HTML_OPEN=never`. Other bindings produce reports differently (xUnit/JUnit XML, pytest output) — match the repo's convention.

## Green-path runs are not driven by an agent

In Helix, the deterministic test pass is run as a plain command from the execution plan — no `hc-ui-tester` agent in the loop. The agent is only invoked when:

1. **Authoring** new tests, or
2. **Debugging** a failure that survived Playwright's auto-retry.

This keeps the green path zero-cost in agent tokens.

## Recommended Playwright config for the failure path

For the failure-driven debug flow to work, the target repo's Playwright config should set:

- `retries: 1` — auto-retry once before surfacing as a real failure (flake guard)
- `trace: 'on-first-retry'` — capture a full trace on the retry so the agent can inspect what went wrong
- `screenshot: 'only-on-failure'` — Playwright's default; the agent reads these from the HTML report

If these are missing, the debug-mode agent should propose adding them as part of its fix.

## Debugging a failing test

When invoked in debug mode, the agent has the failing test name, the path to `playwright-report/index.html`, and any captured trace files. Most failures can be diagnosed from the trace alone — open the HTML report and read the timeline.

If trace inspection is insufficient, run the focused test with `--debug=cli` (or the binding's equivalent) in the background. This pauses the test at the start and prints debugging instructions including a session name.

```bash
# TypeScript example
PLAYWRIGHT_HTML_OPEN=never npx playwright test --debug=cli
# ... waits, prints session name like "tw-abcdef" ...

playwright-cli attach tw-abcdef
```

**IMPORTANT**: run the test command in the background and wait for the "Debugging Instructions" output before attaching.

Once attached, use `playwright-cli` to inspect the page, snapshot the DOM, evaluate expressions, etc. Each action emits codegen which can be transcribed into the test (in the target language) when the fix involves a locator or expectation change.

## Default assumption when debugging

Read this every time you enter debug mode:

> The test is correct. The code under test is wrong. Investigate the code first. Modifying the test to make it pass requires recording the justification (what about the test was wrong, and why) in the task log before the change is made. Do not delete or weaken assertions to achieve green.

After fixing, stop the background test run and rerun the focused test to confirm green.
