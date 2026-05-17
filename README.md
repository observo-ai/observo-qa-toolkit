# observo-qa-toolkit

A Claude Code plugin that ships seven QA skills covering the cycle from raw meeting notes to Playwright test results pushed back to [Observo](https://observoai.co):

`prd` → `requirements-testing` → `observo-test-cases` → `observo-code-verifier` → `observo-review-test-case` → `pw-generate` → `pw-run`

Repo-agnostic. Works on any Playwright project — the only hardcoded contract is the `@observo:<code>` tag that links a spec to an Observo case. Spec layout, Page Object Model usage, selectors registry, tier vocabulary, default project — all auto-discovered, or configured via an optional `.observo-toolkit.json` file in your repo root.

> Looking for the platform itself? Sign up at https://observoai.co — this plugin works against any Observo account (hosted or self-hosted).

---

## Table of contents

- [What it is](#what-it-is)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [First workflow](#first-workflow)
- [The 7 skills](#the-7-skills)
- [End-to-end QA workflow](#end-to-end-qa-workflow)
- [Advanced](#advanced)
- [Contributing & versioning](#contributing--versioning)

---

## What it is

`observo-qa-toolkit` bundles seven skills covering the QA lifecycle:

- write a PRD from raw input,
- test the PRD itself for ambiguity / gaps / conflicts,
- generate Observo test cases from the cleaned-up PRD,
- (optionally) ground those scenarios in real source code,
- review test cases against a 15-criteria quality checklist,
- generate Playwright `.spec.ts` files for the approved cases,
- run Playwright and write results back to Observo (case status, step status, attachments, coverage report).

The plugin is **repo-agnostic** — the only hardcoded convention is the `@observo:<code>` tag that links a Playwright test to an Observo case. Everything else (paths, conventions, default project) is discovered at runtime or read from an optional `.observo-toolkit.json` file.

---

## Prerequisites

- **Claude Code** installed.
- **Observo account** with an account-scoped API key (Settings → API Keys → New).
- **Playwright** in your project (for `pw-generate` / `pw-run`). If your repo does not have Playwright yet: `npm create playwright@latest`.

---

## Install

### Quickstart (recommended) — `/plugin install`

Two commands inside Claude Code:

```
/plugin marketplace add observo-ai/claude-plugins
/plugin install observo-qa-toolkit@observo-ai-plugins
```

After the plugin lands, set up access to the platform:

1. **Get your API key** at https://observoai.co (Settings → API Keys).
2. **Configure the Observo MCP server.** Add this block to your MCP config (e.g. `~/.config/claude/mcp.json` or `~/.claude/mcp.json`):

   ```jsonc
   {
     "mcpServers": {
       "observo": {
         "type": "http",
         "url": "https://mcp.observoai.co",
         "headers": { "Authorization": "Bearer ${OBSERVO_API_KEY}" }
       }
     }
   }
   ```

   Export the key in the environment Claude Code runs in:

   ```sh
   export OBSERVO_API_KEY="<paste from dashboard>"
   ```

3. **Drop a config file in your repo root** (optional, all fields optional):

   ```sh
   cp .observo-toolkit.example.json .observo-toolkit.json
   $EDITOR .observo-toolkit.json
   ```

   The example lives at the root of this plugin repo — copy it into the consumer project. See [`.observo-toolkit.json` reference](#observo-toolkitjson-reference) below for the schema.

### Alternative — official Anthropic marketplace

Once the plugin is accepted into `claude-plugins-official`, this will work too:

```
/plugin install observo-qa-toolkit@claude-plugins-official
```

### Fallback — `git clone` (advanced)

For air-gapped environments or older Claude Code without `/plugin install`:

```
git clone https://github.com/observo-ai/observo-qa-toolkit.git ~/.claude/plugins/observo-qa-toolkit
```

Then complete steps 1–3 above.

---

## First workflow

End-to-end smoke — from raw notes to Playwright tests writing results back to Observo. Each block below is something you type in Claude Code.

Draft a PRD:

```
write a PRD from these notes:
<paste meeting notes or feature description>
```

Once the PRD is saved, sanity-check it:

```
review the requirements in ./docs/PRDs/<feature>.md
```

Generate test cases in Observo:

```
create test cases for ./docs/PRDs/<feature>.md
```

(Optional) Ground scenarios in real code — auto-invoked from the previous skill when `observo-code-verifier` is in scope and the repo is readable.

Review what was generated:

```
review test case OB-12
```

or for a whole suite:

```
score the test cases in suite OB-AUTH
```

Generate Playwright `.spec.ts` files for the approved cases:

```
generate Playwright tests for OB-12..OB-49
```

Run Playwright and write results back to Observo:

```
/pw-run
```

The skill picks (or creates) an Observo run, executes Playwright, pushes per-case and per-step status, uploads screenshots / traces / videos on failure, and always emits a 4-bucket coverage report (Linked / Unautomated / Unlinked / Stale).

---

## The 7 skills

| Skill | What it does | Example trigger |
|---|---|---|
| `prd` | Writes a structured PRD from raw input. Body English by default; language configurable via `prd_language`. | "write a PRD from these notes" |
| `requirements-testing` | Reviews a PRD / requirement / Jira ticket for ambiguity, completeness, conflicts, testability, missing AC. | "review the requirements for `<X>`" |
| `observo-test-cases` | Generates test cases and pushes them to Observo (status `IN_REVIEW` by default). Auto-invokes the verifier and the requirements gate when available. | "create test cases for `<feature>`" |
| `observo-code-verifier` | Grounds draft scenarios in actual source code (endpoint paths, error strings, validation rules). Gracefully degrades when there is no code access. | "verify these scenarios against the code" |
| `observo-review-test-case` | Reviews one or more Observo cases against a 15-criteria quality checklist; posts per-issue comments via MCP; assigns a 0–10 score; flips status to `CHANGES_REQUESTED` when comments were created. | "review test case OB-12" |
| `pw-generate` | Generates Playwright `.spec.ts` files, wired to Observo via the `@observo:<code>` tag. Repo-agnostic discovery. | "generate Playwright tests for OB-12..OB-49" |
| `pw-run` | Runs Playwright and writes results back to Observo. Coexists with an in-repo `observo-reporter.ts` when present (skips duplicate writeback). | "/pw-run", "run e2e and push to Observo" |

---

## End-to-end QA workflow

The phases mirror what is shown in [First workflow](#first-workflow); pick whichever apply. Skip any phase you don't need.

### Phase 0 — PRD (`prd`)

**Trigger:** raw meeting notes / feature description, no structured doc yet.

**Output:** Markdown file at `<prd_save_dir>` from `.observo-toolkit.json` (fallback `./docs/PRDs/`). Sections: Overview / Problem Statement / Goals / Non-Goals / User Stories / Data Model / API / UI / Integrations / Acceptance Criteria / Out of Scope.

### Phase 1 — Requirements quality gate (`requirements-testing`)

**Trigger:** you want to confirm the PRD / requirement is testable, complete, and conflict-free before generating cases.

**What it checks:** clarity, completeness, conflicts, testability, missing AC.

**Output:** a categorised list of defects with severity badges (blocker / major / minor), literal quotes from the source, and concrete suggested fixes. Posts to Jira as a comment when a Jira MCP server is connected; otherwise prints to console.

### Phase 2 — Test case generation (`observo-test-cases` + `observo-code-verifier`)

**Trigger:** requirements are clean; time to create cases.

**What happens:**

1. The skill reads the source doc.
2. (Auto) — invokes `requirements-testing` as a quality gate when AC are weak.
3. Projects scenarios from AC: happy / negative / boundary / security / integration / idempotency.
4. (Auto) — invokes `observo-code-verifier` to ground scenarios in code when filesystem access is available.
5. Locates / creates the Observo suite. Runs a semantic duplicate check.
6. Resolves the assignee (config / memory / one-time ask).
7. Calls `mcp__observo__bulk_create_test_cases` for the whole batch.
8. Default `status=IN_REVIEW`.

The skill then offers to scaffold automation for the new cases — grouped by `layer` (E2E / API / UNIT) — and routes each group to the appropriate scaffolder (`pw-generate` for E2E, an external API test builder for API, etc.).

### Phase 3 — Review test cases (`observo-review-test-case`)

**Trigger:** freshly created cases are in `IN_REVIEW`; you want a systematic QA pass before `APPROVED`.

**What it does:**

1. Runs each case through a 15-criteria checklist (title, atomicity, executable steps, expected result, scope tagging, etc.).
2. Posts per-issue review comments via MCP in the correct scope (`CASE` / `FIELD` / `STEP`).
3. Assigns a 0–10 score.
4. Flips status to `CHANGES_REQUESTED` if comments were created.

The skill never edits the case body, resolves comments, or approves cases — those remain human decisions.

### Phase 4 — Generate Playwright specs (`pw-generate`)

**Trigger:** cases are `APPROVED` (Mode A — Observo codes) or the PRD is good enough to drive scenarios directly (Mode B — PRD path).

**What happens:**

1. Discovery — reads `.observo-toolkit.json` (`.observo-pw.json` still supported for backward compat) and auto-detects Playwright config / spec dir / Page Object pattern / selectors registry / fixtures / tier vocabulary.
2. Resolves the source (Observo codes / PRD / inline).
3. Generates `.spec.ts` files — every test carries `@observo:<code>` plus an optional tier tag. Selectors are `data-testid` / `getByRole`; `waitForTimeout` is forbidden.
4. Scaffolds a Page Object and adds testids to the selectors registry **only** when the consumer repo already uses those patterns.
5. Runs `tsc --noEmit` + `playwright test --list` before reporting done.

The skill does **not** flip `automation_status` to `AUTOMATED` — that happens after a green run, as an explicit human decision.

### Phase 5 — Run + writeback + coverage (`pw-run`)

**Trigger:** ready to run and want results in Observo.

Default invocation:

```
/pw-run
```

Re-push after a crash (skip the rerun):

```
/pw-run --reuse-results --run RUN-42
```

CI gate on coverage:

```
/pw-run --fail-on-coverage-gap
```

**What happens:**

1. Same discovery as `pw-generate`.
2. By default runs `npx playwright test --reporter=json,html,list`. `--reuse-results` opts out of the rerun.
3. Resolves the target Observo run: `--run <key>` → sidecar `.observo-metadata.json.runKey` → `--create-run` (interactive confirm) → fail.
4. Reporter coexistence: if the sidecar exists AND `OBSERVO_REPORTER_ENABLED=true`, the in-repo `observo-reporter.ts` already pushed everything; the skill only emits the coverage report.
5. Full writeback otherwise: per-case status + comment, per-step status (when step counts match), case-level attachments on `FAILED` / `BLOCKED`, run-level `results.json` as an event log (always).
6. **Coverage report — always.** 4 buckets: Linked / Unautomated / Unlinked / Stale.
7. `--fail-on-coverage-gap` (opt-in) → exit 2 if `Unautomated > 0 || Stale > 0`.
8. Finalises the run unless `--keep-open` was passed.

Status mapping (matches in-repo reporter):

| Playwright | Observo |
|---|---|
| `passed` | `passed` |
| `passed` after retry | `passed` + comment `Passed on retry Nx` |
| `failed` | `failed` (with `error.message` + stack) |
| `skipped` | `skipped` |
| `timedOut` / `interrupted` | `blocked` |

---

## Advanced

### `.observo-toolkit.json` reference

All fields are optional — the plugin falls back to sensible defaults when the file is missing.

```jsonc
{
  // PRD skill defaults
  "prd_save_dir": "docs/PRDs",
  "prd_language": "en",                   // body language: "en" | "ru" | "ua" | …
  "prd_headings_language": "en",          // always-on safer default

  // Requirements / test-case skill defaults
  "requirements_dir": "docs/requirements",
  "default_observo_project": "MYPROJ",
  "default_assignee": "qa@mycompany.com",

  // Playwright discovery (also accepted from legacy .observo-pw.json)
  "playwright_root": "e2e",
  "spec_dir": "e2e/tests",
  "pages_dir": "e2e/pages",
  "selectors_file": "e2e/utils/selectors.ts",
  "selectors_export": "TestIds",
  "fixtures_dir": "e2e/fixtures",
  "tier_tags": ["@prod-safe"],
  "tier_tag_required": true,
  "reporter_path": "e2e/reporters/observo-reporter.ts",
  "metadata_file": "e2e/playwright-report/.observo-metadata.json",

  // Telemetry (opt-in, default false; see TELEMETRY.md)
  "telemetry_enabled": false
}
```

### Self-hosted MCP server

`mcp.observoai.co` is the recommended path. For on-prem or air-gapped setups, run the Observo MCP server yourself and point the plugin at it — same JSON config, different `url`. See the main Observo docs for self-host instructions.

### CI integration

`pw-run --fail-on-coverage-gap` exits with code 2 when there are unautomated or stale cases. Wire that into your pipeline, for example with GitHub Actions:

```yaml
- name: Run e2e + push to Observo + gate on coverage
  run: /pw-run --fail-on-coverage-gap
  env:
    OBSERVO_API_KEY: ${{ secrets.OBSERVO_API_KEY }}
    OBSERVO_REPORTER_ENABLED: "true"   # in-repo reporter writes per-test as Playwright runs
```

If you already have an `observo-reporter.ts` doing inline writeback, `pw-run` detects the sidecar and skips duplicates — only coverage runs.

### `@observo:<code>` tag — the join key

The only hardcoded contract in the plugin. Every Playwright test linked to an Observo case must carry one tag matching the regex `^@observo:([A-Z]+-\d+)$`. Tags that do not match this pattern are tier tags or freeform — fine, just not parsed as the join key.

```typescript
test(
  'User cannot log in with incorrect password',
  { tag: ['@prod-safe', '@observo:OB-12'] },
  async ({ page }) => { /* ... */ },
);
```

---

## Contributing & versioning

- **Semver.** Bumps follow https://semver.org. Major for breaking changes to skill descriptions or the config schema; minor for new skills; patch for fixes and doc updates.
- **Changelog.** See [CHANGELOG.md](CHANGELOG.md) — updated with every release.
- **Issues.** File bug reports and feature requests at https://github.com/observo-ai/observo-qa-toolkit/issues.
- **Telemetry.** Server-side telemetry (anonymized, aggregate of MCP tool calls) is on for the hosted MCP — see [TELEMETRY.md](TELEMETRY.md) for the full event-field list. The plugin-side opt-in beacon is off by default; enable it via `.observo-toolkit.json:telemetry_enabled`.
- **License.** MIT — see [LICENSE](LICENSE).
