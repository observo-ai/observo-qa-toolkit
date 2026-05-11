---
name: observo-code-verifier
description: Verifies a set of designed test scenarios against actual source code before they are pushed to Observo (or any other test management platform). Checks endpoint paths, error message strings, validation rules, and field names against handler code, proto files, and validators. Gracefully degrades when source code is not accessible (e.g., when invoked by a QA team without repo access) — in that case, returns the scenarios unchanged and clearly flags that verification was skipped. Use when you have a draft set of scenarios derived from a PRD / requirements doc and want to ground them in the actual implementation before recording them anywhere. Triggered by phrases like "verify test cases against code", "ground these scenarios in implementation", "check error messages match the code", "code-verify these tests", or invoked from observo-test-cases as an optional pre-create step.
---

# Observo Code Verifier

Ground PRD-derived test scenarios in the actual implementation, so error message strings, endpoint paths, validation rules, and field names match what the code really does. Optional, **non-blocking**: if there's no code access, the skill returns scenarios unchanged with a clear flag.

## When to use

- A scenario set was designed from a PRD / requirements doc / as-built doc, but the doc may have drifted from code.
- Before pushing the scenarios anywhere (Observo, Jira, spreadsheet), you want to verify literal strings (error messages, endpoint paths) that automation will assert against.
- Invoked from `observo-test-cases` between *Design* and *Create*, or stand-alone.

## When NOT to use

- The scenarios are pure UX prose with no code-checkable claims (e.g. "user feels confident") — nothing to verify.
- The user already said "don't bother with code verification" or specified speed over accuracy.

## Inputs (expected in handoff)

The invoker should provide, in plain text:

1. **Source doc path** (if any) — e.g. `knowledge-base/04-Product/Requirements/01-Auth-Accounts.md`.
2. **Scenario list** — at minimum: name + key claims that could be code-verified. Either inline JSON or a textual list. Each scenario should expose:
   - Expected HTTP endpoint path (if applicable)
   - Expected error message string (if applicable)
   - Expected validation rule (if applicable, e.g. "password 8–100 chars, ≥1 uppercase, ≥1 digit, ≥1 special")
   - Field / payload / response shape claims

If nothing of the above is in the scenarios, there's nothing to verify — return early and say so.

## Step 1 — Detect code access

Try sources of code in this order; stop at the first that works:

1. **Local filesystem (CWD as repo root):** run `Bash`: `ls -d server web-portal worker mcp 2>/dev/null | head` (or `ls package.json go.mod Cargo.toml pyproject.toml 2>/dev/null`). If any common project marker is present, the repo is local — use `Read` / `Grep` / `Bash` for the rest.
2. **MCP server for repo browsing.** If any tool with name matching `mcp__*github*`, `mcp__*gitlab*`, `mcp__*git*`, `mcp__*filesystem*`, `mcp__*sourcegraph*`, or similar is registered in this session, use it. Resolve the repo to inspect from context (the source doc usually lives in a repo path the user is already working with).
3. **None.** No filesystem access, no repo MCP. **Don't fail.** Return the scenarios unchanged with `verification: skipped (no code access)` on each. Add one summary line: "Code verification skipped — install/connect a repo MCP or run from the project root for grounded verification."

Set a variable `code_source = "filesystem" | "mcp:<server-name>" | "none"` to surface in the summary.

## Step 2 — Verify (only if `code_source != "none"`)

For each scenario, attempt to verify each claim it makes. **Use grep / search — never read whole files unless necessary.** The patterns below assume a typical repo; adapt to whatever's actually there.

### 2a. Endpoint paths

For Go/proto repos: `grep -nE 'path:\\s*"<path>"|"<method>:\\s*\\"<path>\\""' server/proto/*.proto` and `grep -rn '<path>' server/api/ server/handlers/ 2>/dev/null`.

For Node/Express/Fastify: `grep -rnE 'app\\.(get|post|put|patch|delete)\\(\\s*"<path>"' src/ routes/ 2>/dev/null`.

For Python/FastAPI/Flask: `grep -rnE '@(app|router)\\.(get|post|put|patch|delete)\\(\\s*"<path>"' .` 

Confirm each scenario's endpoint path exists. If not found, mark the scenario `verification: endpoint-mismatch` with the closest-matching real path as a suggestion.

### 2b. Error message strings

For each error string the scenario asserts (e.g. `"email not found"`):

```
grep -rnEi '"<error-string>"' server/ src/ services/ handlers/ 2>/dev/null | head -20
```

If found verbatim → `verification: ok`. If found in a different wording → `verification: string-drift` with both versions side by side and a suggestion to update the scenario. If not found at all → `verification: error-string-missing`, suggest the most likely actual string from nearby handler code.

### 2c. Validation rules (lengths, ranges, regex)

Look in `val/`, `validators/`, `validation/`, or near the relevant handler:

```
grep -rnE 'min(\\.|=|\\()|max(\\.|=|\\()|regex|MinLen|MaxLen|Length|range' val/ validators/ 2>/dev/null
```

Compare the numeric thresholds / regex to the scenario's claim. Mark accordingly.

### 2d. Field / payload / response names

For claims like "session has user-agent and IP fields", grep proto / schema:

```
grep -rnE '(user_agent|ip|email|account_id)' server/proto/*.proto server/db/ 2>/dev/null
```

### 2e. Optional integrations (only if mentioned)

For claims like "background job `send_verify_email` is queued":

```
grep -rn 'send_verify_email\\|configure_account\\|send_forgot_password_email' worker/ server/ 2>/dev/null
```

If the task name in code differs (e.g. `SendVerifyEmail` in Go), normalize and mark accordingly.

## Step 3 — Return annotated output

For each scenario, emit a structured entry:

```yaml
- name: "Login — unknown email returns 'email not found'"
  verification:
    code_source: filesystem
    status: ok | string-drift | endpoint-mismatch | missing | skipped
    notes: short reason
    suggested_corrections:
      - field: error_message
        was: "email not found"
        now: "user with this email not found"
        evidence: server/api/login.go:42
  scenario: <original payload, unchanged unless explicitly corrected>
```

**Critical: never silently mutate scenarios.** Mark drifts; the human (or the invoking skill) decides whether to apply suggestions.

Aggregate counts at the top of the response:

```
verification_summary:
  code_source: filesystem
  total: 49
  ok: 38
  string_drift: 7
  endpoint_mismatch: 2
  missing: 2
  skipped: 0
```

If `code_source == "none"`, all entries are `skipped` and the summary states it once at top — no per-entry noise.

## Step 4 — Summary to user

Short, actionable:

1. One-line headline: "Verified 49 scenarios against `server/` (filesystem). 38 ok, 7 string-drift, 2 endpoint-mismatch, 2 missing."
2. Bullet list of the **drifts** with `was` / `now` / `evidence` paths — sorted by risk (endpoint-mismatch > string-drift > missing).
3. If invoked by another skill: hand back the annotated scenario list so the caller can decide whether to apply corrections before pushing to Observo.

## Hard rules

- ❌ **Never block.** If code access fails halfway through, finish with whatever was verified and mark the rest `skipped`. Always return scenarios.
- ❌ **Don't fix code.** This skill is read-only against the codebase. Even if you spot bugs in handlers, don't edit them.
- ❌ **Don't fabricate evidence.** Every `suggested_corrections.evidence` must be a real file:line that you actually saw in grep output. If you can't find evidence, mark `status: missing` and stop — don't guess.
- ❌ **Don't read whole files when grep would do.** Repos can be huge; respect context budget.
- ❌ **Don't refuse to verify ambiguous cases.** Mark `status: missing` with a short reason instead of stalling.
- ✅ **Do degrade gracefully.** No code? Return scenarios unchanged + one line "skipped, reason X". The caller / user can still proceed.
- ✅ **Do prefer proto/schema/handler files** as primary evidence over docs (docs may have drifted, that's exactly what this skill exists to catch).
