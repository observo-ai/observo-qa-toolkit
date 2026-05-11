---
name: pw-sync
description: >-
  Sync Playwright tests with Observo — the test management platform for this
  repo. Use when the user mentions "Observo", "test management", "test cases",
  "test run", "sync test cases", "push results to Observo", "import from
  Observo", "запушити результати в Observo", "створити ран в Observo", or any
  Playwright ↔ Observo bridging task.
---

# Observo Integration

Bidirectional sync between Playwright tests and the Observo test management platform.

## Prerequisites

The `observo` MCP server must be registered in the session — its tools appear as `mcp__observo__*`. If they're not visible, stop and tell the user that the `observo` MCP server isn't connected (check `.mcp.json` at the repo root and `API_KEY` env var).

## Capabilities

### 1. Import Observo Cases → Generate Playwright Tests

```
/pw-sync import --project <code> --suite <code>
```

Steps:
1. Call `mcp__observo__list_test_cases` (filtered by `project_id` / `suite_id`, default filter `status=APPROVED` AND `automation_status != AUTOMATED`) to fetch the case batch worth automating.
2. For each case, call `mcp__observo__get_test_case` to pull title, description, pre/post-conditions, and the ordered `steps[]` array (action / data / expected).
3. Map the case to a Playwright template — read the matching file under `~/.claude/plugins/cache/claude-code-skills/pw/2.2.2/skills/pw/templates/`:
   - `layer=API` → `templates/api/`
   - name contains "login" / "signup" / "auth" → `templates/auth/`
   - name contains "checkout" / "payment" → `templates/checkout/`
   - name contains "search" / "filter" → `templates/search/`
   - name contains "form" / "submit" → `templates/forms/`
   - name contains "dashboard" → `templates/dashboard/`
   - name contains "settings" / "profile" → `templates/settings/`
   - name contains "onboarding" → `templates/onboarding/`
   - name contains "accessibility" / "a11y" → `templates/accessibility/`
   - otherwise → `templates/crud/`
4. Generate the test file with the Observo case code pre-wired as an annotation (see *Test Annotation Format* below).
5. Group specs by suite — one file per Observo suite (`tests/<suite-slug>.spec.ts`), unless the user names another layout.
6. Don't flip `automation_status` to `AUTOMATION_STATUS_AUTOMATED` yet — that happens after a real green run, not at import time.
7. Report: X cases imported, Y test files generated, list of paths.

### 2. Push Test Results → Observo

```
/pw-sync push --run <run-code>
```

Steps:
1. Run Playwright with JSON reporter (or reuse the latest report on disk):
   ```bash
   npx playwright test --reporter=json,html > playwright-report/results.json
   ```
   Reuse existing `results.json` if it's fresh — don't re-run unprompted.
2. Parse results. For each test, extract:
   - `title`
   - `annotations[]` filtered to `type === 'observo'` → take `description` as the case code (e.g. `OB-123`). A test may carry several.
   - Playwright `status` mapped to Observo status using the *Status mapping* table further down (right above *Create Test Run*).
   - `error.message`, `error.stack` (failed only).
   - `attachments[]` — paths to `screenshot.png`, `video.webm`, `trace.zip`.
3. For each annotated test, call `mcp__observo__update_case_in_run` with `run_id`, `case_id`, `status`, and `comment`. If a test carries multiple `observo` annotations, fan out — push the same result to every listed case.
4. **Per-step granularity (optional):** if the Playwright test uses `test.step('...')` and the Observo case has matching ordered `steps[]`, parse step results from the JSON report and call `mcp__observo__update_step_in_run` per step. Match by index. If step counts differ → skip step-level push, log it in the summary.
5. **Attach artefacts for failures:** for every FAILED / BLOCKED case, call `mcp__observo__upload_attachment` for `trace.zip`, `screenshot.png`, `video.webm` (target = the case-in-run record). Don't upload artefacts for passing tests.
6. **Close the run** only if the user asked or all expected cases reported — call `mcp__observo__update_run` with status COMPLETED and a one-line summary: `"Playwright @ <branch> <commit> — X passed, Y failed, Z skipped"`. Never auto-close a run that was opened by someone else.
7. Report: run code + counts (pushed / passed / failed / skipped / blocked / unlinked) and list of unlinked tests (no `observo` annotation).

#### Status mapping (used in step 2 above)

| Playwright | Observo |
| --- | --- |
| `passed` | `PASSED` |
| `passed` after retry | `PASSED` + comment `Passed on retry N×` |
| `failed` | `FAILED` (include `error.message` as comment) |
| `skipped` | `SKIPPED` |
| `interrupted` or `timedOut` | `BLOCKED` — couldn't determine pass/fail, not the same as a failed assertion |

### 3. Create Test Run

```
/pw-sync run --project <code> --name "Sprint 42 regression"
```

Steps:
1. Discover annotated tests — grep the repo for `type: 'observo'` annotations and collect every case short code. Pattern:
   ```
   type:\s*['"]observo['"][\s\S]{0,80}?description:\s*['"]([A-Z]+-\d+)['"]
   ```
2. Resolve short codes → case UUIDs by listing cases for the project (`mcp__observo__list_test_cases`) and matching on `code`. Fail loudly on unresolved codes (stale annotations).
3. Call `mcp__observo__create_run` with:
   - `project_id`
   - `name` (from `--name` or default `Playwright @ <branch> <YYYY-MM-DD HH:MM>`)
   - `case_ids[]` — UUIDs from step 2
4. Return the run code (e.g. `RUN-42`) to the user — that's what they pass to `push` via `--run`.

### 4. Sync Status

```
/pw-sync status --project <code> [--suite <code>]
```

Steps:
1. Fetch all cases for the project / suite via `mcp__observo__list_test_cases`. Collect `{code, id, name, automation_status}`.
2. Scan the repo for `observo` annotations → set of codes referenced by Playwright tests.
3. Report 4 buckets:

   ```
   Observo cases in scope: N
   Playwright tests with observo annotations: M

   Linked       (Observo case + Playwright test):   X
   Unautomated  (Observo case, no Playwright test): Y   ← coverage gaps
   Unlinked     (Playwright test, no Observo case): Z   ← needs annotation or backfill
   Stale        (annotation points at missing code): W
   ```

4. For each bucket, list the top 20 items. Write the full list to `pw-sync-status.md` if the user asks.
5. Don't auto-create cases for unlinked tests — offer to invoke the `observo-test-cases` skill if the user wants to backfill.

### 5. Update Test Cases in Observo

```
/pw-sync update --case <code>
```

When the Playwright test for a case drifted from what Observo records as its steps, sync code → Observo.

Steps:
1. Find the Playwright test annotated with that case code.
2. Extract the ordered steps from the test:
   - Each `test.step('...')` block → one step.
   - Inside each block, derive `action` (the imperative summary), `data` (any input the test types or sends), and `expected` (the `expect(...)` assertion target). If the test doesn't use `test.step`, treat the whole body as a single step and prompt the user to split it.
3. Call `mcp__observo__update_test_case` to write the new `steps[]`. Pass any enum fields in the prefixed form (`PRIORITY_HIGH`, `CASE_TYPE_FUNCTIONAL`, `BEHAVIOR_POSITIVE`, …). OB-241 fixed silent drops on create/update via MCP normalization (2026-05-11); read the case back to confirm if you suspect a stale MCP build.
4. Report: case code + number of steps written, plus any dropped fields.

## MCP Tools Used

- `mcp__observo__list_projects` — list available projects.
- `mcp__observo__list_suites` — list suites in a project.
- `mcp__observo__list_test_cases` — read test cases (with filters).
- `mcp__observo__get_test_case` — read a single case with full steps.
- `mcp__observo__update_test_case` — update an existing case.
- `mcp__observo__create_run` — create a test run.
- `mcp__observo__list_runs`, `mcp__observo__get_run` — locate or inspect a run.
- `mcp__observo__update_run` — mark a run COMPLETED, add summary.
- `mcp__observo__get_case_in_run` — read a case's current status in a run.
- `mcp__observo__update_case_in_run` — push pass/fail per case.
- `mcp__observo__update_step_in_run` — push per-step status (1:1 step mapping only).
- `mcp__observo__upload_attachment` — attach screenshots / videos / traces to failures.

## Test Annotation Format

Every Playwright test linked to Observo carries an annotation with the case short code:

```typescript
test('should login successfully', async ({ page }) => {
  test.info().annotations.push({
    type: 'observo',
    description: 'OB-123',
  });
  // ... test code
});
```

This annotation is the join key between Playwright and Observo. A test without it is treated as *unlinked* — invisible to every workflow above. One test may carry multiple `observo` annotations if it legitimately covers several atomic cases (rare — the `observo-test-cases` skill produces atomic cases on purpose).

## Defaults

- Default project = `OB` (Observo E2E) unless the user names another.
- Default run name = `Playwright @ <branch> <YYYY-MM-DD HH:MM>`.
- Default behavior on `flaky` = treat as `PASSED`, flag retries in the run comment. Override per team policy if asked.
- Default on `interrupted` / `timedOut` = `BLOCKED`, not `FAILED`.

## Anti-patterns

- ❌ Closing a run before all expected cases reported. If Playwright partially crashed (worker died), keep the run OPEN and push what you have — the user can re-run and push again.
- ❌ Pushing results without surfacing the *unlinked* count. Silent drops hide coverage gaps.
- ❌ Re-running `npx playwright test` when a fresh `results.json` exists on disk.
- ❌ Calling `bulk_create_test_cases` from this skill — delegate to `observo-test-cases` for case creation, keep concerns separate.
- ❌ Flipping `automation_status` to `AUTOMATION_STATUS_AUTOMATED` at import time. Only after a real green run.
- ❌ Calling any `delete_*` tool without explicit user confirmation — deletes are irreversible.

## Output

For every capability:
- Operation summary with counts (pushed / created / imported / flagged).
- Run code + case codes touched.
- Any tool errors or fields the MCP layer silently dropped.
- One suggested next action — push, import, status, or stop.
