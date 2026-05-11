---
name: observo-test-cases
description: Generate test cases for a feature, requirement, or PRD and push them to the Observo test management platform with sensible defaults — status=IN_REVIEW and assignee = current user. Use when the user asks to "створи тест кейси", "напиши test cases", "create test cases", "push test cases to Observo", "test cases for <module/requirement>", or similar. If the user did not explicitly say whether they want Observo records or local Jest/RTL/Playwright code, ask first via AskUserQuestion before doing anything.
---

# Observo Test Cases Skill

Workflow for creating test cases in **Observo** (a test management platform — see https://observoai.co). The deliverable is *records in Observo*, created through the Observo MCP server. If the user's intent is ambiguous between Observo records and local test code (Jest / RTL / Playwright / Vitest / etc.), this skill **asks first** rather than assuming — see *Disambiguation* below. Local test code generation is out of scope for this skill — the user can invoke whatever QA / test-scaffolding skill they normally use for that.

## Trigger

The user asks (UA or EN) to write/create/push test cases for a feature, requirement, PRD, module, or knowledge-base doc. Phrases like:
- "створи тест кейси для <X>"
- "напиши test cases на <module>"
- "create test cases for <feature/requirement>"
- "push test cases to Observo"

## Disambiguation — when intent is unclear, ASK

"Test cases" can mean two different deliverables:
1. **Observo records** — scenarios stored in the Observo test management platform (this skill).
2. **Local test source code** — Jest / RTL / Playwright / Vitest / etc. test files in the repo. Not handled by this skill — the user invokes their own QA / test-scaffolding skill for that.

**Before touching anything, if the user did NOT explicitly say which one, ask once via `AskUserQuestion`** — two options:
- "Push to Observo (test management records, IN_REVIEW, assigned to me)" → continue with this skill.
- "Generate local test code (Jest / RTL / Playwright / Vitest)" → stop this skill and let the user invoke their preferred test-scaffolding skill for that.

Skip the question only if the user already named the target explicitly. Strong signals for this skill: "Observo", "test management", "IN_REVIEW", "assign to me", "push to platform". Strong signals for local-code path: "Jest", "Playwright", "Vitest", "spec file", "`.test.ts`", "`.spec.ts`", "scaffold tests", "unit tests in the repo".

Do NOT assume the default. Asking is cheap; pushing 50 cases to Observo when the user wanted local Jest stubs (or vice versa) is expensive to undo.

## Workflow

### 1. Identify the source

The "feature/requirement" usually lives under `knowledge-base/04-Product/Requirements/` (as-built docs) or `knowledge-base/04-Product/PRDs/`. Read the doc end-to-end. The Acceptance Criteria list is the primary source of test scenarios.

### 1a. Requirement quality gate (optional, recommended)

A weak / ambiguous / incomplete requirement produces weak test cases — "garbage in, garbage out". Before designing scenarios, evaluate whether the source itself needs work:

1. If the skill `requirements-testing` appears in this session's available-skills list, and either:
   - the source doc has no clear Acceptance Criteria section, **or**
   - the user explicitly asked to review requirements first, **or**
   - the user-facing language in the doc is vague (a lot of "should", "may", "as needed", "fast", "user-friendly"),
   
   then **invoke `requirements-testing` via the `Skill` tool** before step 2, passing as handoff the source path / Jira key / inline text.
2. If `requirements-testing` finds **blocker** defects (conflicts, fundamental clarity gaps), stop and surface them — ask the user via `AskUserQuestion` whether to:
   - **Fix the requirement first** (default) — return the findings, end this skill; user updates the source and re-invokes.
   - **Proceed anyway** — continue to step 2, but flag in the final summary that test cases were generated against an un-cleaned requirement.
3. If only **major / minor** defects are found, surface them in passing but continue to step 2 — they're polish, not blockers.
4. If `requirements-testing` is NOT in the available-skills list, skip this gate and proceed; mention in the final summary that the gate was skipped and the plugin's requirements-testing skill can be installed to enable it.

### 2. Design the test set

Cover every distinct Acceptance Criterion as its own scenario. Heuristics:

- **Happy paths** — each user-visible action with valid inputs.
- **Negative / validation paths** — one case per distinct error message named in the AC. Don't collapse them.
- **Boundary conditions** — input lengths, counts, time windows (e.g. "code valid 15 minutes" → both a happy case and an "expired" case).
- **Security and permission boundaries** — auth required, role gates (Owner/Admin/User/Guest), cross-account isolation, anti-enumeration responses, token forgery / expiry, replay/reuse detection.
- **Integration touchpoints** — background jobs, OAuth callbacks, Stripe webhooks, email send/bounce, third-party calls — one case each, mocking the external piece in `pre_conditions` if needed.
- **Idempotency / replay** — re-doing the action twice (re-verify already-verified email; presenting a consumed one-time token; reuse-detection on rotated refresh tokens).
- **Concurrency / race conditions** — only when the AC actually calls them out; otherwise out of scope.
- **"Out of Scope (Future)" items in the source doc** → do **NOT** create cases. They're not implemented yet.
- **Open Questions in the source doc** → do **NOT** create cases. The behavior isn't decided yet.

One scenario = one test case. Atomic. If a scenario has multiple ordered steps, those go into the case's `steps[]` array — they are NOT separate cases. The test of "atomic" is: each case should fail for exactly one reason.

**Caveat — PRD ≠ code.** As-built / reverse-engineered docs drift from real handler code over time, especially literal error message strings, endpoint paths, and validation thresholds. Step 2a below grounds the design in code when possible. Without it, scenarios reflect *what the PRD claims*, not *what the code actually does* — automation built on top will brittle-fail on mismatches.

### 2a. Code-verification (optional, graceful)

After sketching scenarios in step 2 and BEFORE pushing to Observo, try to ground them in the implementation:

1. If the skill `observo-code-verifier` appears in this session's available-skills list → **invoke it via the `Skill` tool**, passing as handoff:
   - source doc path
   - the draft scenario list with at-minimum: name + any code-checkable claims (endpoint paths, error message strings, validation rules)
2. The verifier will return an annotated list with statuses (`ok` / `string-drift` / `endpoint-mismatch` / `missing` / `skipped`) and `suggested_corrections` with `was` / `now` / `evidence` per drift.
3. Decision policy on the returned annotations:
   - `ok` → no change.
   - `string-drift` (error message wording differs) → apply the suggested correction silently (it's a literal fact pulled from code). Mention count in summary.
   - `endpoint-mismatch` (path doesn't exist) → DON'T silently fix. Ask the user once via `AskUserQuestion` whether to use the verifier's suggestion or drop the scenario.
   - `missing` (claim couldn't be located in code) → keep the scenario but flag it for the user in the summary so they can verify manually.
   - `skipped` (no code access) → proceed with the original scenarios; flag in the summary that verification was skipped and what would help next time (e.g. "run from project root, or connect a repo MCP server").
4. If `observo-code-verifier` is NOT in the available-skills list → proceed without verification, but add to the summary: "Code verification skipped — install the `observo-code-verifier` skill (ships with this plugin) for grounded test cases."

**Never block creation** on verifier output. Worst case (skipped + many missing) → create cases anyway, flag everything in the summary so the user can review.

### 3. Discover Observo target

- If the user hasn't specified a project, call `mcp__observo__list_projects`. Default to "Observo E2E" (`OB`) unless told otherwise.
- Suite: `mcp__observo__list_suites` for the project. If a suite matching the module already exists, reuse its `suite_id`. Otherwise `mcp__observo__create_suite` with `name` = module title (e.g. "Auth & Accounts") and a short `description` linking to the source doc.
- **Duplicate check (semantic, not just name-match):** call `mcp__observo__list_test_cases` with `suite_id` and pull names + descriptions of all existing cases in that suite. For each newly-designed scenario, compare *intent* — not just the literal name string — against the existing set. Two cases are duplicates if they verify the same behavior on the same area, even when worded differently (e.g. "Login with unknown email returns 'email not found'" ≈ "Reject login when email is not registered"). Rules:
  - Clear match (same area + same expected outcome) → skip the new one, mention skipped count in the summary.
  - Borderline (similar area, possibly different angle) → keep the new one but flag it for the user in the summary (so they can merge/delete in review).
  - No match → create.
  - When the suite has many cases (>50), batch the comparison by area/feature block from the source doc to keep it tractable.

### 4. Resolve assignee

Every case must be assigned to a user. The default assignee is the **current user themselves** (they want to review what's generated). Resolution chain:

1. **From memory** — if a project-scoped memory entry stores the user's Observo email and/or UUID for this purpose (e.g. an entry named like "Observo default assignee"), use it.
2. **Resolve email → UUID via MCP** — call `mcp__observo__list_account_users` with `search=<email>` and take the matching user's `id`. Use the resolved UUID for both `owner_id` and `reviewer_id`.
3. **First-run ask** — if memory has no email yet, ask the user once via `AskUserQuestion` for their Observo email, then save it to a memory entry so future sessions don't need to ask again.
4. **Hard fallback** — if `list_account_users` is not registered in this session (older MCP server build) and the user can't paste their UUID, create the cases without `owner_id` / `reviewer_id` and **clearly flag in the summary** that assignee was skipped. Do not silently drop the requirement.

### 5. Create the cases

Use `mcp__observo__bulk_create_test_cases` (single call for the whole batch). Per-case payload:

| Field | Value |
|---|---|
| `name` | short scenario title (≤80 chars). Format: `"<area> — <expected outcome>"` |
| `description` | 1–2 sentences on what's tested and why |
| `suite_id` | from step 3 |
| `status` | `IN_REVIEW` by default. If the user explicitly named a different status (`DRAFT` / `APPROVED` / `CHANGES_REQUESTED` / `DEPRECATED`), use that. If status was not mentioned at all, ask once via `AskUserQuestion` with `IN_REVIEW` as the recommended option — see *Status policy* below |
| `owner_id`, `reviewer_id` | UUID from step 4 |
| `severity` | BLOCKER \| CRITICAL \| NORMAL \| MINOR \| TRIVIAL — judged from AC criticality |
| `priority` | HIGH \| MEDIUM \| LOW |
| `layer` | E2E \| API \| UNIT (mostly E2E or API for Observo records) |
| `type` | FUNCTIONAL \| SECURITY \| REGRESSION \| INTEGRATION \| SMOKE \| ACCEPTANCE \| … |
| `behavior` | POSITIVE \| NEGATIVE \| DESTRUCTIVE |
| `automation_status` | `MANUAL` by default |
| `pre_conditions`, `post_conditions` | when material |
| `steps` | ordered array of `{action, data, expected}` — Action / Data / Expected. Atomic. |

### 5a. Status policy

Default status for every freshly generated case is **`IN_REVIEW`** — the user needs to review batched output before promoting it. But this is a default, not a hard rule:

- If the user explicitly named a status in their request (`status=APPROVED`, "create as draft", "помісти в approved" тощо) → honour it.
- If the user did NOT mention status at all → ask **once** via `AskUserQuestion` with options:
  1. **`IN_REVIEW` (Recommended)** — needs my review before approval
  2. `DRAFT` — work-in-progress, not ready for review
  3. `APPROVED` — skip review (use sparingly)

Ask the status question only when intent is otherwise unambiguous (i.e. you already know it's Observo records, not Jest code). If you're already disambiguating Observo-vs-Jest, you can combine both questions into a single `AskUserQuestion` call with two questions, to avoid two pop-ups in a row.

### 6. Known limitations (re-check after each MCP release)

Some Observo MCP server builds silently drop certain enum fields on create/update — pass them anyway, but verify after the call:

- After `bulk_create_test_cases` / `create_test_case`, read back one or two cases and check whether `priority`, `type`, `behavior` actually persisted (or came back as `PRIORITY_NOT_SET` / `CASE_TYPE_OTHER` / `BEHAVIOR_NOT_SET`).
- If any field didn't persist, mention it explicitly in the summary — never imply success on a field that didn't apply.
- If `update_test_case` rejects a field with `invalid parameters`, that's the same class of bug — fall back to leaving the field unchanged and surface the gap.

This guidance is defensive against known bug classes in the Observo MCP layer; once the fix is in, the verification step still does no harm.

### 7. Summary to user

After creation, report:
1. Suite (code + id) and total count of cases created.
2. Per-AC-block coverage table — so the user can spot missed scenarios.
3. Assignee status — either "all assigned to <email>" or, if fallback triggered, the explicit gap and how to close it.
4. Any fields that didn't persist due to known bugs (see step 6).

Skip any prose narration about *what you did internally* — the user sees the diff in Observo. Focus the summary on what they need to review.

### 8. Offer automation handoff (active, not just a suggestion)

The natural follow-up after Observo cases land is to automate them as local test code. This skill **actively offers and invokes** that handoff — but lets the user choose, and stays portable.

Steps:

1. **Ask once via `AskUserQuestion`** whether to automate now. Three options:
   - **Yes, automate now** — proceed to step 2.
   - **Not yet — wait until I review/approve in Observo** — skip the handoff; finish with a one-line reminder that the user can re-trigger automation later.
   - **No automation planned** — skip the handoff entirely.

   Skip this question (default to "wait") if the chosen status was `DRAFT` (cases aren't ready for automation).

2. **Pick the scaffolding skill** the user prefers:
   - Default candidate: `engineering-skills:senior-qa` (covers Jest + RTL + Playwright scaffolding). Use it if it appears in the current session's *available skills* list.
   - If the default candidate is NOT available, ask the user (via a second `AskUserQuestion`) for the exact name of their preferred scaffolding skill, OR offer "skip — I'll do this manually later".
   - Never hard-code an assumption that `senior-qa` exists. The skill name is a default, not a dependency.

3. **Invoke the chosen scaffolding skill** via the `Skill` tool:
   ```
   Skill(skill="<chosen-skill-name>")
   ```
   Before invoking, prepare a tight handoff brief in plain text so the next skill has context — keep it under ~10 lines:
   - Source doc path (e.g. requirements file)
   - List of Observo case codes that should map to generated specs (e.g. `OB-1..OB-49`) — pull from the bulk_create response
   - Preferred output language / framework if the user named one (else let the scaffolding skill ask)
   - Reminder to wire CI to push results back to Observo runs via the Observo MCP (`create_run` / `update_case_in_run` / `update_step_in_run`)

4. **After the scaffolding skill returns**, summarize what landed (number of spec files, paths) and confirm the user can now run them locally / in CI.

If the user chose "wait" or "no" in step 1: end with one short line — "Automation skipped; re-trigger when you're ready by asking to 'automate the approved cases' or by running `<scaffolding-skill-name>` directly."

## Anti-patterns

- ❌ Assuming "test cases" means Observo records when the user's intent is ambiguous — always disambiguate first (see *Disambiguation* above). Local test code (Jest / RTL / Playwright / Vitest / …) is a valid alternative deliverable; if the user picks it, stop this skill and let them invoke whatever scaffolding skill they prefer.
- ❌ Auto-picking `APPROVED` or `DRAFT` without checking with the user. Default is `IN_REVIEW`; other statuses require either an explicit user instruction or an answer from the disambiguation question.
- ❌ Multiple scenarios in one test case — atomic only.
- ❌ Skipping the semantic duplicate check, or doing it as a literal name-string compare only. A scenario worded slightly differently but verifying the same behavior is still a duplicate — see step 3.
- ❌ Calling delete tools without explicit user confirmation.
- ❌ Pretending priority/type/behavior persisted when they didn't (the backend bug).
- ❌ Silently dropping assignee — if you can't resolve UUID, say so in the summary.
