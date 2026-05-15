---
name: pw-run
description: >-
  Run Playwright tests and write results back to Observo — case status, step
  status, error comments, screenshot/trace/video attachments on FAILED, and the
  full `results.json` as a run-level event-log attachment (PRD-Playwright-Skills
  D2). Always emits a 4-bucket coverage report (Linked / Unautomated / Unlinked /
  Stale) at the end. Repo-agnostic — discovers Playwright layout from
  `.observo-pw.json` (or auto-detects). Coexists with in-repo
  `observo-reporter.ts` — detects sidecar `.observo-metadata.json` and skips
  duplicate work the reporter already did. Use when the user asks "запусти
  тести і запиши в Observo", "run e2e + push results", "pw-run", "re-push run
  results", or any request whose deliverable is `cd <project> && npx playwright
  test` + writeback to Observo via MCP.
---

# Playwright Runner + Observo Writeback (repo-agnostic)

Runs Playwright tests (or reuses a fresh `results.json` via `--reuse-results`) and writes every result back to Observo via MCP. Sibling to `pw-generate`: that skill generates `.spec.ts`; this one runs them and reports.

## Scope — what this skill IS and ISN'T

- **IS:**
  - Run Playwright (default) or parse existing `results.json` (`--reuse-results`).
  - Resolve target Observo run via priority: `--run <key>` → sidecar `.observo-metadata.json.runKey` → `--create-run` (creates a fresh run via MCP).
  - Per-case writeback: `mcp__observo__update_case_in_run` with mapped status + comment.
  - Per-step writeback when Playwright `test.step()` count == Observo case `steps[]` count.
  - Attachments on FAILED/BLOCKED: screenshot/trace/video → `mcp__observo__upload_attachment` scope=run_case.
  - Run-level attachment **always**: full `results.json` → `mcp__observo__upload_attachment` scope=run (event log for ontology, PRD D2).
  - 4-bucket coverage report at end, always.
  - Optional CI gate: `--fail-on-coverage-gap` → exit 2 if `Unautomated > 0 || Stale > 0`.
  - Reporter coexistence: if sidecar `.observo-metadata.json` exists AND `OBSERVO_REPORTER_ENABLED=true`, the in-repo reporter already wrote per-case/per-step/attachments — skip duplicates; do **only** coverage + summary.
- **ISN'T:**
  - Generating new specs → `pw-generate`.
  - Creating Observo test cases → `observo-test-cases`.
  - Flipping `automation_status` to AUTOMATED — explicit human decision, post-green-run.
  - Scaffolding a fresh Playwright project (no `playwright.config.*` in repo) — tell user to `npm create playwright@latest` first.

## Architectural note — runner-specific today, generic seam tomorrow

This skill is the **Playwright adapter** for an Observo run-and-report flow that will likely generalize. Most of what's documented below is **runner-agnostic**:

- Resolving / auto-creating the Observo Run (Mode A / Mode B, plan resolution, single confirm).
- Mapping runner result statuses to Observo `PASSED | FAILED | SKIPPED | BLOCKED`.
- Per-case / per-step writeback via `mcp__observo__update_case_in_run` / `update_step_in_run`.
- Attachment upload (case-level evidence on FAILED + run-level `results.json` event log).
- 4-bucket coverage report (Linked / Unautomated / Unlinked / Stale) and CI gate.
- Sidecar-based reporter coexistence.

The **Playwright-specific** parts are narrow:

- `npx playwright test` invocation and exit-code semantics.
- Parsing `playwright-report/results.json` (the `suites[].specs[].tests[]` shape, `tags[]` field, attachments list).
- The `@observo:<code>` tag convention is hardcoded here but is itself runner-agnostic — any runner that can emit tags / metadata could carry it.

When a second runner (Cypress, pytest, Selenium, etc.) shows up with a real ask — not before, per `feedback_solo_infra_demand_gate` — refactor into:

- `test-run` skill — owns all the Observo-side orchestration listed above.
- `pw-run` / `cypress-run` / `pytest-run` skills — adapters that implement a small contract: invoke the runner, parse its results into a normalized shape `{ case_codes, status, steps, attachments, duration }`, hand it to `test-run` for writeback.

Until that ask exists, keep this skill self-contained — premature abstraction with one implementation is a maintenance tax with no payoff.

## Trigger

User asks (UA/EN) to run e2e tests + push results to Observo:
- "запусти тести і запиши в Observo"
- "/pw-run", "/pw-run --run RUN-42 --reuse-results"
- "run e2e and sync to Observo"
- "push playwright results to RUN-42"
- "re-push the last run after the crash"

## Workflow

### 1. Repo discovery (D5 contract — no hardcoded paths)

Same 3-tier resolution as `pw-generate`:

**Layer A — read `.observo-pw.json`** (or `observo.pw` section in `package.json`) in repo root. Fields used by this skill:

```jsonc
{
  "playwright_root": "e2e",                                // dir containing playwright.config.*
  "spec_dir": "e2e/tests",                                 // testDir override
  "metadata_file": "playwright-report/.observo-metadata.json",  // sidecar contract written by observo-reporter
  "default_observo_project": "OB",                         // short code; no global default
  "reporter_path": "e2e/reporters/observo-reporter.ts"     // detection only — env-driven enable
}
```

(Other fields like `pages_dir`, `selectors_file`, `tier_tags` exist for `pw-generate` but this skill ignores them.)

**Layer B — auto-discovery** for unset fields:
- Find `playwright.config.{ts,js,mjs}` anywhere (excluding `node_modules/`).
- Parse `testDir`, `projects[].testDir`, `reporter` from the config (best-effort).
- Default `metadata_file` = `<playwright_root>/playwright-report/.observo-metadata.json`.
- Default `results_json` path = `<playwright_root>/playwright-report/results.json` (matches what `pw-generate`'s JSON reporter writes).

**Layer C — `AskUserQuestion` fallback** for what neither layer resolved. Offer to write the answer to `.observo-pw.json`.

**Discovery snapshot** (in-memory):
```
PlaywrightRoot:     <dir>
SpecDir:            <dir>
ResultsJsonPath:    <playwright_root>/playwright-report/results.json
MetadataFile:       <playwright_root>/playwright-report/.observo-metadata.json
DefaultObservoProj: <code | null>
```

If `PlaywrightRoot` couldn't be resolved → stop; tell user to set up Playwright first.

### 2. Parse CLI flags

Slash-command argument string after `/pw-run`. Supported flags:

| Flag | Type | Default | Effect |
|---|---|---|---|
| `--run <key>` | string | (unset) | Use this exact run key (e.g. `RUN-42`). Highest priority for run resolution. |
| `--create-run` | bool | false | Create a NEW Observo run via `mcp__observo__create_run` and write its key. Use when there's no existing run to push to. |
| `--plan <plan_key>` | string | (unset) | Force Mode B (test-plan run). Skip plan-picker; use this `plan_key` directly. Triggered automatically by "regression / full suite" phrasing — flag is for scripted/CI flows. |
| `--project <code>` | string | from config | Override `default_observo_project` (e.g. `OB`). |
| `--grep <pattern>` | string | (unset) | Forwarded to `npx playwright test --grep <pattern>`. Ignored in Mode B (plan defines the scope). |
| `--reuse-results` | bool | false | Skip Playwright run; parse existing `<ResultsJsonPath>`. For crash-recovery / re-push. |
| `--keep-open` | bool | false | Don't finalize the run (status COMPLETED). Use when this is a partial push that will be followed by another. |
| `--fail-on-coverage-gap` | bool | false | Exit 2 if `Unautomated > 0 || Stale > 0` after writeback. For CI gating. |

If unknown flags are passed → log warning, continue (don't error out).

### 3. Run Playwright (or reuse)

**Default (`--reuse-results` not passed):**
```bash
cd <PlaywrightRoot> && npx playwright test [--grep <pattern>] --reporter=json,html,list
```

`npx playwright test` may exit non-zero on test failures — that's expected. **Do not** treat non-zero exit from Playwright as fatal; the writeback path needs to run regardless of pass/fail. Capture exit code but continue.

After the run, verify `<ResultsJsonPath>` exists. If not → fail with clear error pointing to playwright.config.ts and the json reporter config.

**With `--reuse-results`:**
- Don't run Playwright.
- Verify `<ResultsJsonPath>` exists and is readable. If missing → fail with `"--reuse-results passed but <path> not found"`.

### 4. Resolve target Observo run (BEFORE running Playwright)

**A Run must exist BEFORE `npx playwright test` is invoked** — `update_case_in_run` / `update_step_in_run` / `upload_attachment(run_case_id=...)` all need a run key to map results to. Resolve the run as the first MCP step in this skill, never after PW execution.

Priority chain — stop at first that succeeds:

1. **`--run <key>` flag** → use this key. Verify it exists via `mcp__observo__get_run`. If not found → fail with `"--run <key> not found in Observo"`.
2. **Sidecar `.observo-metadata.json`** — read `<MetadataFile>`, parse JSON, take `runKey`. Verify via `mcp__observo__get_run`. (Reporter-coexistence path: the in-repo reporter writes the sidecar onEnd of a prior run.)
3. **`--create-run` flag** → auto-create silently (CI / scripted use; no question).
4. **None of the above (interactive default)** → **auto-create with one short confirmation**:
   - Discover the case scope (see step 4A below).
   - `AskUserQuestion` with: proposed name (`"pw-run <ISO-date> — <suite/grep>"`), case scope count, and host. Default option: "Create this run." Alt option: "Cancel — I'll pass --run." Do NOT silently auto-create at this branch; user just typed "run the tests" without context, so confirm once.
   - On confirm → call `mcp__observo__create_run`.

**Never fail at step 4 with "pass --create-run" or similar.** Auto-creating with confirmation is the default UX — the user said "run the tests"; producing a run for them is part of that.

### 4A. Pick run-scope mode (case-list vs test-plan)

`mcp__observo__create_run` takes exactly one of `plan_key` / `case_ids` / `suite_ids`. Which one to use depends on **what the user is running** — that intent is in the trigger phrase, not in flags.

**Mode A — case-list (default).** Trigger: any specific PW invocation — `/pw-run`, `/pw-run --grep <X>`, "run smoke", "run the login spec", "rerun OB-5". Build `case_ids` from the `@observo:<code>` tags in the specs that will execute (see step 4A.1).

**Mode B — test-plan (regression / full suite).** Trigger: "регресія" / "regression", "повний прогін" / "full suite", "run the plan", "/pw-run --plan", or any phrasing where the user wants to run a curated Observo Test Plan rather than just whatever specs Playwright matches. In this mode the user is asserting an Observo-side scope (the plan), so we let Observo expand it to case_ids server-side — call `create_run` with `plan_key` and let the run track exactly what the plan defines.

**Choosing when phrasing is ambiguous** (e.g. "прогни тести"): default to Mode A. Don't silently switch to Mode B without an explicit signal — case-list mode is safer because it scopes the run to what PW actually executes.

### 4A.1. Mode A — build case_ids from PW specs

1. Determine which specs PW will run — same `--grep <pattern>` filter the user passed (or all specs in `<SpecDir>` if no grep).
2. Run `npx playwright test --list --reporter=json [--grep <pattern>]` (or parse spec files) to enumerate test entries with their `tags[]`.
3. Filter tags by `^@observo:([A-Z]+-\d+)$`. Collect unique codes.
4. Resolve each code to a UUID via `mcp__observo__list_test_cases` (filter by `code=`); skip codes that don't resolve (will be reported as **Stale** in coverage).
5. If `case_ids` is empty → fail before creating an empty run: `"No @observo:<code> tags found in the matched specs — nothing to run against Observo. Add tags or pass --plan."`

### 4A.2. Mode B — resolve the test plan

1. Fetch plans for the resolved project — `mcp__observo__list_test_plans(project_id)` (or REST `GET /api/projects/{project_id}/plans` while the MCP wrapper is being built; see "Open follow-ups" below).
2. **Filter to active plans only** (skip archived / draft per server schema).
3. Pick:
   - **0 plans** → fail with: `"Project has no test plans. Create one in Observo first, or use case-list mode without --plan."`
   - **1 plan** → use it silently. Mention name in the discovery snapshot (`Plan: <name> (single plan, no question asked)`). **Do NOT ask** — there's no choice.
   - **>1 plans** → `AskUserQuestion` listing plans (one option per plan, with name + case count + last-updated). **One option must be "Cancel — I'll specify the plan"** so the user can bail.
4. After selection (silent or asked), if no `--yes` flag passed, confirm once: "Running plan **`<name>`** (`plan_key=<key>`, ~`<N>` cases) — create run?". This is the **same single confirm** as Mode A's step 4.4 — don't double-prompt.
5. Use `plan_key` in `create_run`; do not pass `case_ids` alongside.

### 4A.3. `create_run` payload

**Mode A:**
```
project_id:  <resolved UUID — from --project / config / list_projects+ask>
name:        "pw-run <YYYY-MM-DD HH:MM> — <suite-or-grep>"
description: "Auto-created by pw-run skill for <N> Observo case(s): <code1>, <code2>, ..."
host:        <process.env.BASE_URL — discovered from playwright.config.ts or .env>
case_ids:    [<UUID>, <UUID>, ...]
```

**Mode B:**
```
project_id:  <resolved UUID>
name:        "pw-run <YYYY-MM-DD HH:MM> — plan <plan-name>"
description: "Auto-created by pw-run skill from plan <plan-name> (<plan_key>)"
host:        <process.env.BASE_URL>
plan_key:    <plan_key>
```

Capture `run.run_key` (e.g. `RUN-42`) from response. This is the `runKey` used for the rest of the workflow.

### 4B. Confirm before MCP write — once

A confirm-once UX prevents accidental run pollution but doesn't pester. The single `AskUserQuestion` from step 4.4 happens **only** in interactive default branch (no `--run`, no sidecar, no `--create-run`). Once the user confirms (or passes `--create-run` upfront), no further questions in this skill invocation.

Save resolved `runKey` for the rest of the workflow.

### 5. Detect reporter coexistence

If `<MetadataFile>` exists AND contains a `runKey` AND `OBSERVO_REPORTER_ENABLED=true` was set when Playwright ran (heuristic: check env at this skill invocation — if user just ran Playwright with env, the in-repo reporter already pushed):

- **Coexistence mode ON.** Per-case, per-step, attachments, and run-level `results.json` upload — **already done by the reporter**. Do NOT re-push.
- Skip directly to step 9 (coverage report) and step 10 (summary).
- Mention "reporter-coexistence active: skipped writeback (already done by in-repo observo-reporter)" in summary.

Otherwise — coexistence mode OFF; do the full writeback below.

### 6. Parse `results.json` and resolve case codes

Read `<ResultsJsonPath>`. For each test in `suites[].specs[].tests[]`:

- Extract `tags[]`; filter via regex `^@observo:([A-Z]+-\d+)$`. Capture each matched code. A test may carry multiple — fan out writeback to all of them.
- Tests with NO `@observo:` tag → add to **Unlinked** bucket (coverage report). Don't writeback.
- For each captured code, resolve to Observo via `mcp__observo__list_test_cases` (filter `code=`). If not found → add to **Stale** bucket; warn and skip.
- For each resolved case, fetch full content with `mcp__observo__get_test_case` to get `steps[]` count (needed for step-mismatch check).

Aggregate per test:
```
{ playwright_test_id, observo_codes: [...], status, error?, duration_ms, attachments: [...], steps: [...] }
```

### 7. Per-case writeback

For each `(playwright_test, observo_code)` pair where the code resolved:

```
mcp__observo__update_case_in_run
  run_id: <runKey>          // accepts short code
  case_short_code: <observo_code>
  status: <mapped>
  comment: <error message + stack, only on FAILED/BLOCKED; or "Passed on retry Nx" if retry>
```

**Status mapping** (must match the in-repo reporter):
| Playwright | Observo |
|---|---|
| `passed` | `passed` |
| `passed` (after retry) | `passed` + comment `"Passed on retry Nx"` |
| `failed` | `failed` |
| `skipped` | `skipped` |
| `timedOut` | `blocked` |
| `interrupted` | `blocked` |

### 8. Per-step writeback

For each test where `playwright_test.steps` filtered to `category='test.step'` count **equals** the Observo case's `steps[]` count:

For step index `i` (0-based) → step_number `i+1`:
```
mcp__observo__update_step_in_run
  run_key: <runKey>
  case_short_code: <observo_code>
  step_number: <i+1>
  status: <mapped from step.error presence>
  comment: <step.error.message if present>
```

If counts mismatch → skip step-level for this test entirely; log diff to summary as `step-mismatch: <code> playwright=N observo=M`.

### 9. Attachments — case-level on FAILED/BLOCKED + run-level always

**Two upload paths — pick by file size, not by preference:**

| Raw file size | MCP inline (`upload_attachment`) | Helper (`./upload-attachments.sh`) |
|---|---|---|
| **< ~50 KB** | fine, ~16K tokens | also works |
| **~50–190 KB** | expensive, up to ~85K tokens | preferred |
| **> ~190 KB** | **impossible** — Claude's Read tool hard-caps file content at 256KB (~190KB raw after the ×1.333 base64 expansion). The tool can't ingest the file to build the JSON arg in the first place. | required |

So the helper isn't just a token-cost optimization. Above ~190KB raw it is the only path. Below that the line is soft — measured tokens vs convenience.

The helper script lives next to this SKILL.md (`upload-attachments.sh`) and uses the same `/api/projects/{project_id}/attachments:upload` endpoint with an API key from env (`OBSERVO_API_KEY` / `E2E_ACCOUNT_API_KEY`). Same scope rules (run / case / step), same validation. It also stream-builds the JSON payload (base64 piped straight into a temp file) so it doesn't hold a `~Nx` copy in shell heap — relevant when uploading a 100MB video on a 512MB CI container.

**Case-level (FAILED/BLOCKED only):**
For each attachment in `playwright_test.attachments` (screenshot/trace/video):

- **`results.json` snippet, small screenshots (<50KB)** — use `mcp__observo__upload_attachment` inline:
  ```
  mcp__observo__upload_attachment
    project_id: <project UUID>
    file_name: <attachment.name>
    content_type: <attachment.contentType>
    content: <base64 of file at attachment.path>
    run_id: <runKey>
    run_case_id: <observo_code>
  ```

- **`trace.zip`, `video.webm`, large evidence** — invoke the helper:
  ```bash
  ./upload-attachments.sh \
    --file "<attachment.path>" \
    --project-id "<project UUID>" \
    --run-id "<runKey>" \
    --run-case-id "<observo_code>"
  ```
  Returns `{id, storage_url, scope, file_name, content_type, bytes}` JSON on stdout.

Skip `playwright_test.attachments` whose `name` is `console` or who have no `path` (no file on disk).

**Run-level (always, regardless of pass/fail):**
Once per pw-run invocation, upload the full `results.json`. For typical suites this file is a few KB and MCP-inline is fine. **For large suites it can blow past 50KB and even past 190KB** (a project with 500+ test cases easily hits that). Check `wc -c playwright-report/results.json` before choosing the path — if it's over 50KB use the helper; the same size-tier table above applies. Otherwise inline:
```
mcp__observo__upload_attachment
  project_id: <project UUID>
  file_name: results.json
  content_type: application/json
  content: <base64 of ResultsJsonPath contents>
  run_id: <runKey>
  // NO run_case_id — scope=run
```

This is the ontology event log per PRD D2.

**Don't upload** the HTML report (`<PlaywrightRoot>/playwright-report/index.html` + assets) — human artifact, dups `results.json` for machines.

**Decision rule, restated:** if the file is under ~50KB, inline via MCP is fine — but if you're not sure of the size, the helper is the safer default because **MCP inline is impossible above ~190KB raw (256KB Read cap)**, not just expensive. Anything labelled `application/zip` (traces), `video/*`, or above ~50KB — use the helper. The helper always works and never burns model tokens; MCP-inline is the cost optimization for known-small evidence, not the default.

### 10. Finalize run

Unless `--keep-open` was passed:
```
mcp__observo__update_run
  run_id: <runKey>
  status: COMPLETED
  summary: "pw-run @ <branch?> — <X passed, Y failed, Z skipped, W blocked, U unlinked>"
```

Skip finalize if user passed `--keep-open` (they're doing partial push; another `/pw-run` will close it).

### 11. Coverage report — always, after writeback

Regardless of writeback path. Compute 4 buckets:

1. **All Observo cases in project scope** — `mcp__observo__list_test_cases` filter by `project_id` (with pagination if >50 cases).
2. **All `@observo:<code>` tags found in `results.json`** — set captured in step 6.
3. **Bucket each:**
   - **Linked** = Observo case ∩ has Playwright test in results.json.
   - **Unautomated** = Observo case but NOT in results.json tag set → coverage gap.
   - **Unlinked** = Playwright test had NO `@observo:` tag → needs tag or backfill.
   - **Stale** = `@observo:<code>` tag in results.json but no matching Observo case → tag refers to deleted/missing code.

Print summary block (mirror format from PRD AC):
```
Observo cases in scope: N
Playwright tests with @observo: tag: M

Linked       (Observo case + Playwright test):    X
Unautomated  (Observo case, no Playwright test):  Y   ← coverage gap
Unlinked     (Playwright test, no @observo tag):  Z   ← needs tag or backfill
Stale        (tag points at missing code):        W
```

If any bucket has >0 items, list top 20 in each.

### 12. Coverage gap exit code

If `--fail-on-coverage-gap` was passed AND (`Unautomated > 0 || Stale > 0`) → exit with code 2 after summary is printed. Otherwise exit 0 (or whatever Playwright's exit code was, capped at 1 for test failures).

### 13. Summary

Final summary to user:
1. **Resolved run:** key + URL to Observo (if URL pattern known) + which resolution path was used (`--run` / sidecar / `--create-run`).
2. **Reporter coexistence:** active or skipped, and why.
3. **Discovery snapshot** — same one-line block as `pw-generate`.
4. **Writeback counts:** `pushed=X, passed=Y, failed=Z, skipped=W, blocked=V, unlinked=U`.
5. **Step-mismatched cases** with counts.
6. **Uploaded attachments** counts per scope (run / run_case / step).
7. **Coverage report** (block from step 11).
8. **Exit code** — 0 (success), 1 (Playwright had failures), 2 (`--fail-on-coverage-gap` triggered).

## Anti-patterns

- ❌ **Running Playwright before a Run is resolved.** Run resolution is step 4 — it MUST complete before `npx playwright test` is invoked. Otherwise per-case writeback has nowhere to land and attachments leak.
- ❌ **Failing in interactive default branch with "pass --create-run".** When the user types "run the tests", the skill auto-creates the run with one short `AskUserQuestion` confirm. CI flows pass `--run` or `--create-run` upfront.
- ❌ **Creating a Run with empty `case_ids`.** If no `@observo:<code>` tags resolve, surface that before MCP write — empty runs pollute the Run list and confuse coverage reports.
- ❌ **Silently switching from case-list to test-plan mode** because phrasing is ambiguous. Mode B (`plan_key`) is only triggered by explicit signals — "регресія / regression / full suite / run the plan / --plan". On ambiguous phrasing, default to Mode A.
- ❌ **Picking a test plan silently when the project has >1 active plan.** Always `AskUserQuestion` listing plans with case counts. Silent-pick is OK only when there's exactly one active plan; mention "single plan, no choice" in the discovery snapshot.
- ❌ **Passing both `plan_key` and `case_ids` to `create_run`.** Server schema is `oneOf`; passing both is undefined behavior. Pick one mode and stick with it.
- ❌ **Hardcoding paths** (`e2e/`, `playwright-report/results.json`, `OB`). All paths/codes come from discovery (`.observo-pw.json` + auto-detect) per D5. See `pw-generate` for the contract.
- ❌ Re-pushing case/step/attachment when sidecar `.observo-metadata.json` exists and reporter was enabled. The reporter already did the work — duplicates inflate Observo records and S3 storage.
- ❌ Treating non-zero Playwright exit as fatal. Playwright exits non-zero when tests fail — that's a signal to writeback, not a reason to abort.
- ❌ Skipping the run-level `results.json` upload when there are no failures. Run-level upload is the **event log** (PRD D2), independent of pass/fail.
- ❌ Pushing HTML report as an attachment. Human artifact, duplicates `results.json` for machines.
- ❌ **Inlining `trace.zip`, `video.webm`, or any attachment > ~50KB via `mcp__observo__upload_attachment`.** Above ~190KB raw it's impossible (256KB Read cap), and from 50KB to 190KB it burns ~16K to ~85K tokens just to transit the model. Use the `./upload-attachments.sh` helper next to this SKILL.md — same endpoint, same scope rules, no token cost.
- ❌ **Adding a batch / scan-all mode to `upload-attachments.sh`.** One file per invocation is intentional — each upload's scope (run / case / step) is explicit at the call site, failure isolation is trivial (one curl, one exit code), and parallel runs share nothing (both payload and response files use `mktemp`). If a caller needs to upload many files, loop in the caller, not in the helper.
- ❌ Flipping `automation_status` to `AUTOMATED` after green run. Explicit human decision; not in this skill.
- ❌ Closing a run when user passed `--keep-open` or when there are still expected cases unreported (partial push scenario).
- ❌ Calling `mcp__observo__delete_*` from this skill. Ever. Destructive ops are user-driven via natural language with explicit confirmation.
- ❌ Counting tests without `@observo:` tag as Stale. They're Unlinked — different bucket, different fix.
- ❌ Reusing stale `results.json` on default flow. Without `--reuse-results`, always run Playwright fresh.
- ❌ Inventing a default Observo project. If `default_observo_project` not in config and `--project` not passed → ask via `list_projects` + `AskUserQuestion`. Never silently default.

## MCP tools used

- `mcp__observo__list_projects` — resolve project when not in config / not in `--project`.
- `mcp__observo__list_test_plans` — resolve plan in Mode B (regression / full-suite). **Not yet shipped** — see "Open follow-ups". While the wrapper is missing, fall back to REST `GET /api/projects/{project_id}/plans` with the API key, or ask the user for `plan_key` directly via `AskUserQuestion`.
- `mcp__observo__list_test_cases` — resolve `@observo:<code>` → UUID; coverage scope.
- `mcp__observo__get_test_case` — fetch `steps[]` count for step-mismatch check.
- `mcp__observo__list_runs`, `mcp__observo__get_run` — resolve run by key, verify existence.
- `mcp__observo__create_run` — when `--create-run` flag passed.
- `mcp__observo__update_case_in_run` — per-case writeback.
- `mcp__observo__update_step_in_run` — per-step writeback (only when step counts match).
- `mcp__observo__upload_attachment` — case-level (FAILED/BLOCKED) + run-level (always).
- `mcp__observo__update_run` — finalize with status=COMPLETED + summary.

No `mcp__observo__delete_*` tools — ever.

## Defaults

- **Default Observo project:** none hardcoded. Resolution: `--project` → `default_observo_project` in config → `list_projects` + ask. Never silently default.
- **Default behavior:** always run Playwright + parse fresh `results.json`. `--reuse-results` is explicit opt-in for crash-recovery.
- **Run resolution chain:** `--run` → sidecar `.observo-metadata.json.runKey` → `--create-run` → fail.
- **Coverage gate:** OFF by default. Opt-in via `--fail-on-coverage-gap` for CI use.
- **Finalize policy:** close run (COMPLETED) unless `--keep-open` passed.

## Open follow-ups

- **`list_test_plans` MCP wrapper** — Mode B (test-plan run) depends on it. Proto endpoint exists at `GET /api/projects/{project_id}/plans` (and matching `GET /api/projects/{project_id}/plans/{plan_key}`), but `mcp/internal/tools/` has no wrapper today. Until then Mode B uses REST direct with `E2E_ACCOUNT_API_KEY`, or asks the user for `plan_key` upfront. Track separately.

## Handoff

After a successful run:
1. **Failures** — if any FAILED/BLOCKED cases, list them with the Observo case-in-run URL pattern and the trace.zip filename to point user at the right artifact in Observo UI.
2. **Coverage gaps** — if `Unautomated > 0`, suggest invoking `pw-generate` against the unautomated cases to backfill specs.
3. **Stale tags** — if `Stale > 0`, suggest grepping the codebase for those tags and either deleting the tag or restoring the Observo case.
4. **`automation_status`** — remind user that this skill does NOT auto-flip to AUTOMATED. If they want to mark cases as automated after a clean green run, that's a separate natural-language ask: "mark OB-12..OB-49 as automated".
