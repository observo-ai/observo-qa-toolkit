---
name: observo-review-test-case
description: Review one or more Observo test cases against a 15-criteria quality checklist, post per-issue review comments via MCP (scope CASE / FIELD / STEP), assign a compact 0–10 score, and flip status to STATUS_CHANGES_REQUESTED when comments were actually created. Use when the user asks to "review test case", "відревьюй кейс", "rate the quality of cases in suite X", "score test cases", or otherwise wants a systematic QA pass on an Observo case.
---

# Observo Test Case Review Skill

Systematic quality review of test cases stored in **Observo** (a test management platform — see https://observoai.co). The deliverable is *review comments in Observo plus a status bump*, posted through the Observo MCP server. The skill is read-mostly: it never edits the case body, never resolves comments, never approves cases — those remain human actions.

## Trigger

The user asks (UA or EN) to QA-review one or more test cases. Phrases like:
- "відревьюй кейс DEMO-37"
- "review test case DEMO-37"
- "пройдись по саті DEMO-LOGIN і скажи, які кейси слабкі"
- "score these test cases"
- "rate the quality of cases in suite X"

If the target is unclear, **ask once** via `AskUserQuestion`. Options:
- Single case (by short code or UUID)
- Whole suite (by short code or UUID) — pull every case and score each one
- Cancel — user wasn't ready

Skip the question only when the user explicitly named a single case or a suite.

## Workflow

### 1. Resolve target(s)

- **Single case:** call `mcp__observo__get_test_case` with the supplied short code (e.g. `DEMO-37`). On UUID, call the same tool — short-code resolution is server-side and handles both shapes. Keep the returned `id` (UUID) and full case body (`name`, `description`, `pre_conditions`, `post_conditions`, `priority`, `type`, `layer`, `behavior`, `severity`, `status`, `steps[]`, `owner_id`, `reviewer_id`) in memory for the rest of the workflow.
- **Whole suite:** call `mcp__observo__list_test_cases` with `suite_id`. Collect every case. Cap batch size at 10–20 cases per pass — if the suite has more, ask the user once whether to continue with all of them (token cost can be material).

### 2. Pre-read existing review comments (idempotency)

Before evaluating anything, call `mcp__observo__list_review_comments` for the case. Keep the returned `comments[]` keyed by `(scope, field_name, step_id)` so step 7 can deduplicate. A re-run of the skill on the same case must NOT produce duplicate OPEN comments.

### 3. Apply the 15-criteria checklist

Score each criterion as **pass / fail**. Map every fail to a planned comment with the correct scope. Be specific — say what's wrong AND give a concrete reformulation.

| # | Criterion | Comment scope | `field_name` / target |
|---|-----------|---------------|-----------------------|
| 1 | Clear, behavior-describing title (not "Check login") | `FIELD` | `name` |
| 2 | Atomic — one case, one main check | `CASE` | — |
| 3 | Preconditions explicit (user role, system state, test data) | `FIELD` | `pre_conditions` |
| 4 | Steps are concrete user actions (no "verify system") | `STEP` | per offending step |
| 5 | Test data explicit (or templated with `{{variable}}`) | `STEP` (offending step) | — |
| 6 | Expected result is specific (UI message / status / state) | `STEP` (or `FIELD` `expected` at case-level) | per offending step |
| 7 | Action / Data / Expected structure per step | `STEP` | per offending step |
| 8 | Covers positive, negative, edge cases (suite-level signal — fix as comment on the case) | `CASE` | — |
| 9 | Not a duplicate of another case — see §3.9 below for the embedding-based procedure | `CASE` | reference the other short code |
| 10 | Automation-ready (deterministic, stable selectors/fields) | `STEP` or `CASE` | per offending area |
| 11 | `priority` and `type` are set correctly | `FIELD` | `priority` / `type` |
| 12 | Traceability to requirement / PRD / ticket | `CASE` | — |
| 13 | No hidden assumptions (e.g. "admin" referenced but not in preconditions) | `FIELD` | `pre_conditions` |
| 14 | For complex flows: expected covers UI **and** backend state | `STEP` or `FIELD` `expected` | — |
| 15 | Not flaky by design (no bare `wait N seconds`, no shared state, no order dependency) | `STEP` | per offending step |

### 3.9. Criterion #9 — semantic dedup procedure

Call `mcp__observo__find_similar_cases` with:
- `test_case_id`: the case being reviewed
- `scope`: `"project"` (default — duplicates from another project are almost never actionable)
- `min_similarity`: `0.72` (calibrated from OB-250 smoke against `text-embedding-3-small` — real paraphrase pairs sit around cosine 0.65–0.80; 0.85 missed near-duplicates)

How to interpret the response:
- **Empty `results` list** → criterion #9 passes. No comment.
- **Non-empty list** → criterion #9 fails. Take the **top 3** hits (already ordered by cosine desc) and post **one `CASE`-scoped comment per hit** using this exact format:

  > Possible duplicate of `{{short_code}}` (cosine `{{similarity}}`). Decide manually whether this is a true dup before merging.

  Do not collapse multiple hits into a single comment — the user resolves them independently.

Failure / fallback path (do NOT surface an error to the user):
- RPC returns 404 / 503 / network failure → silently fall back to the legacy heuristic: case names within the same suite that share ≥ 80% tokens.
- `results` is empty AND the source case is freshly created (< 30s old) → embedding worker is likely still catching up. Skip the criterion this run; the next review will catch it.



Weights (from PRD):

```
Clear title              1
Atomic scenario          1
Clear preconditions      1
Executable steps         1
Explicit test data       1
Specific expected result 2  ← doubled
Covers relevant risk     1
Automation-ready         1
Linked to requirement    1
─────────────────────────────
Maximum                 10
```

Interpretation:
- **9–10** strong — do NOT post comments, do NOT touch status.
- **7–8** acceptable, minor refinement — post the relevant comments, status → CHANGES_REQUESTED.
- **5–6** weak — post comments, status → CHANGES_REQUESTED, flag "rewrite recommended" in the chat summary.
- **<5** not review-ready — post comments, status → CHANGES_REQUESTED, flag "consider rewriting from scratch" in the chat summary.

### 5. Build the comment plan

For each failed criterion, draft a single comment with:
- `scope` = from the table in step 3
- `field_name` when `scope=FIELD`
- `step_id` when `scope=STEP` (the UUID of the specific offending step from the case body)
- `message` formatted as:
  - **What's wrong** (one sentence)
  - **Suggested fix** (one sentence, imperative — "Rewrite title to 'User cannot log in with incorrect password'")

Default language for the comment text is **English** (matches the case content convention). Default tone is **imperative + concrete reformulation**, never "I suggest" or "maybe consider".

### 6. Deduplicate against existing comments

For each planned comment, check the pre-read list from step 2: if there is already an OPEN comment in the same `(scope, field_name, step_id)` tuple whose `message` substantially overlaps the new draft, **skip it**. Don't post the same finding twice. Track the skipped count for the summary.

If the existing comment is RESOLVED but the issue still applies → post a new one (the human marked the previous discussion done, so this is a regression signal).

### 7. Post the comments

For each surviving comment in the plan, call `mcp__observo__add_review_comment`. One call per comment — don't batch. Capture the returned `comment.id` from each call so the chat summary can list them.

### 8. Bump status if (and only if) comments were created

- If **count of comments newly created in step 7 ≥ 1** AND the case's current `status` ≠ `STATUS_CHANGES_REQUESTED` → call `mcp__observo__update_test_case` with `payload.status = "STATUS_CHANGES_REQUESTED"`. Do NOT change any other field.
- If 0 new comments were created (either no failures or all duplicates) → leave status alone.
- Never set status to `STATUS_APPROVED` no matter the score. Approval is a human action.

### 9. Return the report to the user

Markdown structure:

```
Score: <X>/10 — <strong | acceptable | weak | not review-ready>

| # | Criterion | Pass/Fail | Comment ID (if posted) |
|---|---|---|---|
| 1 | Clear title | … | … |
…

Comments posted:
- <comment-id>: <short quote of the message>
- …

Comments skipped (duplicates of existing OPEN):
- <count>

Status:
- Before: <STATUS_…>
- After:  <STATUS_… or unchanged>
```

For **suite-mode**, prepend an aggregate header:

```
Suite <SHORT-CODE>: N cases reviewed
  Strong (≥9):       <count>
  Acceptable (7–8):  <count>
  Weak (5–6):        <count>
  Not review-ready (<5): <count>
```

Skip prose narration about what you did internally — the user sees the diff in Observo.

## Anti-patterns

- ❌ Posting a comment when score ≥ 9. Strong cases don't get noise — even minor nits.
- ❌ Calling `mcp__observo__delete_review_comment` ever. Delete is a human action; this skill doesn't invoke it.
- ❌ Calling `mcp__observo__update_review_comment` to flip status → RESOLVED on existing comments. Resolve is the author's call in the UI.
- ❌ Calling `mcp__observo__update_test_case` with any field other than `status`. The skill rewrites *nothing* in the case body.
- ❌ Auto-promoting a 10/10 case to `STATUS_APPROVED`. Approval is a human action.
- ❌ Skipping step 2 (`list_review_comments`). Re-runs would otherwise spam duplicate OPEN comments and look broken.
- ❌ Using vague comment text like "expected is vague" without a concrete reformulation. Always give the fix.
- ❌ Mixing comment language with case content language. Default English, stay consistent within one case.
- ❌ Posting more than one comment per failed criterion-and-target. If five steps have vague expected results, that's five separate STEP-scoped comments — but per criterion #6 only.
- ❌ Continuing in suite-mode without checking with the user first if the suite has >20 cases. Token cost on a 200-case suite is material.
- ❌ Telling the user "this might be a duplicate" without a concrete `short_code` reference. A bare cosine score is not actionable feedback.
- ❌ Auto-merging or auto-deleting the case with the highest cosine. The skill marks; the human decides.

## Tools used

| Tool | When |
|---|---|
| `mcp__observo__get_test_case` | Step 1 (single case) |
| `mcp__observo__list_test_cases` | Step 1 (suite mode) |
| `mcp__observo__list_review_comments` | Step 2 (idempotency) |
| `mcp__observo__find_similar_cases` | Step 3.9 (semantic dedup, criterion #9) |
| `mcp__observo__add_review_comment` | Step 7 (post each finding) |
| `mcp__observo__update_test_case` | Step 8 (status bump only) |
| `AskUserQuestion` | Disambiguation, suite-size confirm |

Never invoked by this skill: `delete_review_comment`, `update_review_comment`, `delete_test_case`, `update_steps`, `add_steps`, `delete_step`, `bulk_create_test_cases`, `create_test_case`.

## Caveats

- The 15-criteria checklist is hard-coded here. If a team wants different weights or different style rules (e.g. "every title must start with a verb"), that's a future *Team Style Memory* feature — out of scope for v1.
- Criterion #9 (semantic duplicate detection) is now backed by pgvector embeddings via `mcp__observo__find_similar_cases` (OB-250). The skill falls back to the legacy title-similarity heuristic when the embedding row is missing or the RPC fails — see §3.9.
- Skill never resolves prior OPEN comments even if the underlying issue is now fixed. Author has to mark them resolved manually in the UI.
