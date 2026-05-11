---
name: requirements-testing
description: Test the requirements themselves BEFORE development — analyze a PRD / requirements doc / Jira ticket / user story for ambiguity, completeness gaps, internal conflicts, untestable statements, missing acceptance criteria, and implicit security risks. Outputs a categorised list of issues with concrete suggested fixes (better wording, missing AC, edge cases to add). If a Jira ticket key was provided AND a Jira MCP server is available, posts the findings as a comment on the ticket; otherwise prints the list to the console. Use when the user asks to "тестуй рекваерменти", "перевір PRD", "review requirements", "test the requirements", "requirements testing for <ticket>", "проаналізуй вимоги на ambiguity", "знайди дірки в PRD", "check requirements quality", or names a Jira ticket key with intent to review. NOT for generating test cases (that's observo-test-cases) — this skill stops at fixing the requirement.
---

# Requirements Testing

QA-side review of requirements **before** the team starts coding. The output is a list of defects in the *requirements*, not in the code. Goal: catch ambiguity / missing rules / conflicts / untestable statements / missing AC early — when they're cheap to fix.

This is distinct from `observo-test-cases` (which assumes the requirement is good enough and creates test scenarios for it). When in doubt, run *this* skill first.

## Trigger

User asks (UA / EN) to review or test requirements *as a deliverable*, not yet asking for test cases. Phrases:

- "тестуй рекваерменти"
- "перевір PRD / requirements doc"
- "review the requirements for <X>"
- "знайди дірки / ambiguity у вимогах"
- "requirements testing for <ticket / file>"
- "проаналізуй на повноту / на конфлікти"
- "check requirements quality for <topic>"
- User pastes / names a Jira ticket and asks "що тут не так?", "є проблеми?", "глянь чи нормально"

## Inputs

One of the following must be supplied (ask once via `AskUserQuestion` if it's not clear from the conversation):

- **File path** to a requirements / PRD / spec / user story doc (typical: `knowledge-base/04-Product/Requirements/<file>.md`, `knowledge-base/04-Product/PRDs/<file>.md`).
- **Jira ticket key** (e.g. `OB-123`, `PROJ-456`). Detected as `[A-Z][A-Z0-9]+-\d+` in the user's message.
- **Inline text** (user pasted the user story / requirement directly).
- **Multiple of the above** — e.g. a doc + several linked tickets. Conflict-checking across them is a feature, not a problem.

## Workflow

### 1. Load the source

- File: `Read` the file.
- Jira: detect a Jira-like MCP in this session's tool list. Common name patterns: `mcp__*jira*`, `mcp__*atlassian*`. Use the read-call (e.g. `jira_get /rest/api/3/issue/<KEY>`, or `getJiraIssue` if exposed) to fetch the description and any sub-task list. If no Jira MCP is registered, ask the user to paste the ticket body instead — do not block.
- Inline text: use as supplied.

If the source is a multi-section doc (typical for as-built specs with many ACs), enumerate sections so each defect can be cited by section + line / heading.

### 2. Run the five-axis quality checks

For every distinct requirement / AC bullet in the source, evaluate each axis. **Cite specific quotes** when flagging — never paraphrase the source.

#### 2.1 Clarity

Flag if the requirement leaves *who / what / when / under which conditions* unclear. Specifically:

- Vague modal verbs without conditions: "should", "may", "can" with no actor or trigger.
- Undefined nouns / terms that the doc hasn't established (e.g. "the user" without saying which role).
- Passive voice with no subject ("the transaction is confirmed" — by whom? when? on which event?).
- Pronouns with ambiguous antecedent.

Example of a clarity defect:

> "User should be able to confirm transaction safely." → unclear: which user role? what does "safely" mean here? what triggers confirmation?

#### 2.2 Completeness

For every action / state transition the requirement describes, check whether the doc answers the standard *what-if* checklist:

- Negative paths: what if the input is missing / invalid / duplicated / expired / unauthorised?
- Limits: file sizes, list lengths, time windows, rate limits, retention periods.
- Error handling: which errors are returned? what wording? to whom?
- Concurrency / idempotency: what if the action is retried? two users do it at once?
- Side effects: which background jobs / emails / webhooks / Stripe / Slack events are triggered?
- Cleanup: what gets deleted? what gets retained? PII handling?
- Anti-enumeration / security: same response for existing-vs-non-existing entities where it matters?
- Access control: who is allowed to do this? what roles? cross-account boundary?

When AC is present, walk every AC bullet and ask "what's NOT covered that should be?"

#### 2.3 Conflicts (cross-requirement)

If the source has multiple requirements (sections, tickets, or linked items), look for pairs that contradict. Examples:

- "Transaction can be confirmed only after funds are received" vs "User can confirm transaction immediately after order creation" — direct conflict.
- "Email is unique in the system" vs "User can register with a duplicate email if from a different account" — narrower conflict.
- "All endpoints require Bearer token" vs an endpoint definition that says "no auth needed" — implicit conflict.

If only a single requirement is in scope (one user story, one Jira ticket without linked items), this axis returns `n/a` — say so explicitly rather than silently skipping.

#### 2.4 Testability

A requirement is testable if a QA engineer (or automated test) can deterministically decide pass / fail. Untestable patterns to flag:

- Non-measurable adjectives: "fast", "easy", "user-friendly", "intuitive", "robust", "scalable" without numeric thresholds or observable behavior.
- Subjective verbs: "should look professional", "should feel responsive".
- Conditions without thresholds: "loads quickly" (vs "loads within 2s for up to 10,000 records").
- Promises without observable consequence: "system is secure" (vs concrete: "all PII fields are encrypted at rest using AES-256").

Suggested rewrite for every untestable statement.

#### 2.5 Missing acceptance criteria

If the requirement has no AC section, OR the AC section is shorter / vaguer than the prose body, propose AC bullets that are:

- Concrete (specific actor, action, expected observable outcome)
- Independently verifiable (one AC, one expectation)
- Cover happy path + at least one negative path
- Reference numeric / time limits where the prose implies them

Format proposed AC as a markdown checklist so the user can paste them into the source doc.

### 3. Categorise findings

Each defect gets a structured entry:

```yaml
- id: D-1
  axis: clarity | completeness | conflict | testability | missing-ac | security-risk
  severity: blocker | major | minor
  location: "<doc-section or AC bullet number, with the literal quote>"
  quote: "the exact words from the source"
  issue: "<one-sentence diagnosis>"
  suggested_fix: "<concrete replacement wording, or 'add the following AC: …'>"
  rationale: "<one line on why this matters>"
```

Severity policy:

- **blocker** — the requirement cannot be implemented unambiguously (conflict, fundamental clarity gap, missing key business rule).
- **major** — implementable but at high risk of building the wrong thing (untestable, missing AC, large completeness gap).
- **minor** — wording / polish.

### 4. Output destinations

There are two output paths. Pick based on the input:

#### 4.1 Jira ticket + Jira MCP available → post a comment to the ticket

1. Detect a Jira-like MCP: scan the available tools list for names matching `mcp__*jira*` or `mcp__*atlassian*`. If multiple are registered, prefer the project-scoped one (declared in `.mcp.json`) over global ones; if a host `CLAUDE.md` names a specific Jira MCP to use for this repo, follow that.
2. Format the comment in Atlassian Document Format (ADF) when posting via REST v3, or plain markdown if the MCP wrapper accepts it. Structure:
   - One-line headline with counts (e.g. "Requirements testing — 3 blockers, 5 majors, 2 minors").
   - Per-defect block: severity badge, axis, location quote, suggested fix.
   - Final block: proposed AC checklist (if missing-AC findings exist).
3. Use the appropriate Jira MCP tool. Common variants:
   - Generic REST passthrough (e.g. `mcp__<server>__jira_post`) → `POST /rest/api/3/issue/<KEY>/comment` with ADF body.
   - Atlassian official MCP → `addCommentToJiraIssue` (or similarly named) — pass markdown / ADF as the tool's input requires.
4. After successful post, return to the user: comment URL (or ticket URL with anchor) and a one-line summary.
5. If posting fails → fall back to 4.2 (console output) with a note explaining the failure.

#### 4.2 Otherwise → console list

When no Jira ticket is in scope, OR no Jira MCP is registered, OR posting failed: return the findings inline to the user. Structure:

```
## Requirements testing — <source>

🟥 Blockers (N)
  D-1 · conflict · Section X
  Quote: "…"
  Fix: …
  Why: …

🟧 Major (N)
  D-2 · completeness · AC bullet #3
  Quote: "…"
  Fix: …
  Why: …

🟨 Minor (N)
  D-… · …

## Proposed acceptance criteria

- [ ] …
- [ ] …
```

Plain text, copy-paste ready. No HTML / fancy formatting that won't render in a console.

### 5. Summary line

After either output path, end with one short line so the user knows what to do next:

> "Found N blockers, M majors, K minors. Once the source is updated, you can run `/observo-test-cases` to generate test cases from the cleaned-up requirement."

## Anti-patterns

- ❌ **Generating test cases.** This skill stops at "here's what's wrong with the requirement". Test cases are `observo-test-cases`.
- ❌ **Rewriting the whole requirement.** Flag defects and propose targeted fixes — never replace the user's doc wholesale.
- ❌ **Paraphrasing without quoting.** Every defect must cite the literal text from the source.
- ❌ **Silently skipping the conflict axis** when only one requirement is in scope — explicitly mark it `n/a` so the user knows the check ran.
- ❌ **Refusing to run when no Jira MCP is connected.** Console fallback is a first-class output, not a degraded one.
- ❌ **Posting to Jira without surfacing the comment URL** back to the user.
- ❌ **Fabricating "missing" issues to look thorough.** If the requirement is genuinely complete, say so. False positives erode trust.
- ❌ **Mixing implementation concerns into requirement findings.** Don't say "the handler uses bad regex" — that's code review. Stay at the requirement layer.
