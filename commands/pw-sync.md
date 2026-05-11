---
name: pw-sync
description: Playwright ↔ Observo bridge. Usage: /pw-sync <import|push|run|status|update> [options]
argument-hint: <import|push|run|status|update> [--project <code>] [--suite <code>] [--run <code>] [--case <code>] [--name "<text>"]
---

# /pw-sync

Sync Playwright tests with Observo — import cases as specs, create runs, push results with attachments, report coverage gaps, or update cases from drifted tests.

Arguments: $ARGUMENTS

## Routing

Parse the first positional argument and dispatch:

- `import` → **Observo cases → Playwright specs.** Requires `--project <code>`, optional `--suite <code>`. Generates one spec file per suite, wires `type: 'observo'` annotations, does NOT flip `automation_status` to `AUTOMATED` (that happens after a real green run).
- `push` → **Playwright results → Observo run.** Requires `--run <run-code>` (e.g. `RUN-42`). Uses latest `playwright-report/results.json` if fresh; otherwise re-runs with `--reporter=json,html`. Per-test `update_case_in_run`, per-step `update_step_in_run` when 1:1 step counts match, attaches `trace.zip`/`screenshot.png`/`video.webm` only for FAILED/BLOCKED. Reports unlinked tests.
- `run` → **Create a new Observo run from annotated tests.** Requires `--project <code>`, optional `--name "..."` (default `Playwright @ <branch> <YYYY-MM-DD HH:MM>`). Greps `type: 'observo'` annotations, resolves short codes → UUIDs, calls `create_run`. Returns the run code.
- `status` → **Coverage gap report.** Requires `--project <code>`, optional `--suite <code>`. Four buckets: Linked / Unautomated / Unlinked / Stale.
- `update` → **Sync Playwright steps → Observo case.** Requires `--case <code>`. Extracts ordered `test.step('...')` blocks, writes them to the Observo case via `update_test_case`. Reads back and flags any field the MCP layer silently dropped (known: `priority` / `type` / `behavior`).

If `$ARGUMENTS` is empty or the subcommand is unknown, print the usage line above and stop — don't guess.

## Prerequisites

The `observo` MCP server must be connected — its tools appear as `mcp__observo__*`. If they're missing, stop and tell the user to check `.mcp.json` and the `API_KEY` env var.

## Skill Reference

Full behaviour spec (status mapping, anti-patterns, defaults, MCP tool list, annotation format) lives in the `pw-sync` skill bundled with this plugin:

`.claude/plugins/observo-qa-toolkit/skills/pw-sync/SKILL.md`

Follow that document for every step — this command is a thin dispatch shim over the skill.
