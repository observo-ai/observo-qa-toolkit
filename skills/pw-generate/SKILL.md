---
name: pw-generate
description: >-
  Generate Playwright `.spec.ts` files from a PRD / requirement / Observo test
  case codes, with **repo-agnostic discovery** — works on any Playwright project,
  not bound to a specific directory layout, tier convention, or selectors style.
  The only hardcoded contract is the `@observo:<code>` tag (join key for the
  Observo writeback layer); everything else (spec dir, Page Object usage,
  selectors registry, tier tags, default Observo project) is auto-discovered
  from the consumer repo or read from an optional `.observo-pw.json` config.
  Use when the user asks to "generate Playwright tests", "scaffold Playwright
  spec", "create Playwright tests for <feature>", "convert OB-X / E2E-X to
  Playwright", or any request whose deliverable is local Playwright spec files
  (not Observo records and not a run/report operation).
---

# Playwright Test Generator (Observo-aware, repo-agnostic)

Generates Playwright `.spec.ts` files for **any consumer repo** that has Playwright installed. The deliverable is local test source code wired to Observo via the `@observo:<code>` tag — the only hardcoded convention in this skill. Everything else (where Playwright lives, whether the repo uses Page Object Model, what tier-tags it uses, etc.) is **discovered at runtime** or read from an optional config file.

## Scope — what this skill IS and ISN'T

- **IS** — generate `.spec.ts` files (plus Page Objects / selectors when the consumer repo uses them) from one of:
  1. Observo case codes (e.g. `OB-12..OB-49` or `E2E-007`) — pulled via `mcp__observo__get_test_case`.
  2. A PRD / requirements doc path.
  3. Inline feature description.
- **ISN'T**:
  - Creating Observo records → use `observo-test-cases`.
  - Running tests / pushing run results / creating Observo runs from Playwright JSON → use the `pw-run` skill (sibling skill in this plugin).
  - Scaffolding a fresh Playwright project from scratch (no `playwright.config.*` in repo) — out of scope; tell user to run `npm create playwright@latest` first.

## Trigger

User asks to write Playwright tests / specs / e2e files. Phrases:
- "generate Playwright tests for <feature>"
- "scaffold Playwright spec for OB-23"
- "automate case E2E-007 in Playwright"
- "write Playwright tests for <module>"
- "convert these Observo cases to Playwright code"

Weaker / ambiguous signals — disambiguate first (see below):
- "create test cases for <X>" (could mean Observo records)
- "tests for <X>" (could mean unit tests)

## Disambiguation — when intent is unclear, ASK

"Test cases" can mean two different deliverables:
1. **Local Playwright spec files** — this skill.
2. **Observo records** — `observo-test-cases` skill.

If the user did NOT explicitly say "Playwright" / "spec" / "e2e" / ".spec.ts" / "local code", **ask once via `AskUserQuestion`** before generating anything. Skip the question only if the target is explicit.

## Workflow

### 1. Repo discovery (D5 contract — no hardcoded paths)

Before anything else, learn the consumer repo. **Don't assume** any path; resolve everything via three layers in order:

**Layer A — read optional config `.observo-pw.json`** (or `observo.pw` section in `package.json`) in repo root. Any field present here wins. Schema (all fields optional):

```jsonc
{
  "playwright_root": "e2e",                          // dir containing playwright.config.*
  "spec_dir": "e2e/tests",                           // testDir override
  "pages_dir": "e2e/pages",                          // POM dir; null/absent → POM not used
  "selectors_file": "e2e/utils/selectors.ts",        // centralized testId registry path
  "selectors_export": "TestIds",                     // exported const name
  "fixtures_dir": "e2e/fixtures",                    // custom fixtures dir
  "tier_tags": ["@prod-safe", "@full-stack", "@destructive"],  // ordered: safest → riskiest
  "tier_tag_required": true,                         // false → skip tier-tagging entirely
  "default_observo_project": "OB",                   // short code; no global default
  "reporter_path": "e2e/reporters/observo-reporter.ts",        // custom Observo reporter — read by pw-run, not by pw-generate
  "metadata_file": "e2e/playwright-report/.observo-metadata.json",  // sidecar written by observo-reporter onEnd; read by pw-run for run-key resolution
  "extra_imports": []                                // optional repo-specific imports to add to every spec
}
```

**Layer B — auto-discovery** for whatever Layer A didn't specify:
- Find `playwright.config.{ts,js,mjs}` anywhere in repo, excluding `node_modules/`. If multiple — pick the first by depth (shallowest), or ask via `AskUserQuestion` if there are several equally-shallow ones.
- Parse `testDir`, `projects[].testDir`, `reporter` from the config (best-effort — TS parsing is brittle; if you can't statically read it, ask user or skip).
- Detect POM: look for a `pages/`, `pageObjects/`, `po/`, or `page-objects/` sibling of `playwright.config.*`. First match wins.
- Detect selectors registry: look for `**/selectors.{ts,js}` or `**/testIds.{ts,js}` near `playwright.config.*`. If found, parse the exported const name.
- Detect fixtures: look for a `fixtures/` sibling and list `.ts` files that import `from '@playwright/test'` and call `test.extend`.
- Detect tier tags: read 3-5 existing spec files from `testDir`, collect every tag matching `^@[a-z][a-z0-9-]*$` that's NOT `@observo:...`. The set of recurring tags is the tier vocabulary.

**Layer C — `AskUserQuestion` fallback** for what neither Layer A nor B resolved. Always offer to write the answer to `.observo-pw.json` so future sessions don't ask again.

**Discovery output (in-memory state for the rest of the workflow):**
```
PlaywrightRoot:     <resolved dir>
SpecDir:            <resolved dir>
PagesDir:           <resolved dir | null>
SelectorsFile:      <path | null>
SelectorsExport:    <name | null>
FixturesDir:        <dir | null>
ExistingFixtures:   [<name>, ...]
TierTags:           [<tag>, ...] | []
TierTagRequired:    <bool>
DefaultObservoProj: <code | null>
ExistingSpecPaths:  [<spec>, ...]
```

If `PlaywrightRoot` couldn't be resolved (no config anywhere), stop and tell the user to set up Playwright first.

### 2. Resolve the source

Three input modes; auto-detect from phrasing or ask:

**Mode A — Observo case codes** (e.g. `OB-123`, `E2E-007`, comma list):
1. Resolve project: if user named it, use that; else use `DefaultObservoProj` (from config); else call `mcp__observo__list_projects` + `AskUserQuestion`. **Do not** silently default to any specific code.
2. For each code, `mcp__observo__list_test_cases` (filter `code=`) → UUID, then `mcp__observo__get_test_case` for full content (name, description, pre/post-conditions, `steps[]`, `layer`, `behavior`, `automation_status`).
3. **Skip cases where `automation_status == AUTOMATION_STATUS_AUTOMATED`** unless user explicitly wants overwrite. Flag skips in summary.
4. Group by suite — typically one suite → one `.spec.ts`.

**Mode B — PRD / requirements doc:**
1. Read doc end-to-end. Acceptance Criteria is the primary source of scenarios.
2. Same scenario heuristics as `observo-test-cases` (happy / negative / boundary / security / integration / idempotency).
3. Don't create Observo records here. If the user wants tracking, suggest `observo-test-cases` first.

**Mode C — Inline description:**
1. Ask one round of clarifying questions only if the description is too vague for 1-2 cases.

### 2.5. Resolve Observo Variables + environment (when steps reference `{{placeholder}}`)

If any input case's `steps[].action` / `steps[].data` contains `{{key}}` placeholders, the generated spec must consume Observo **Variables** at runtime — never inline their values into the spec. Variables live in Observo for a reason: single source of truth, swap-per-environment without regenerating tests.

**Workflow:**

1. **Collect placeholders.** Scan every input case for `{{key}}` substrings in `step.action` and `step.data`. Build `Set<key>`.
2. **Resolve environment** for this project:
   - Call `mcp__observo__list_environments(project_id)`.
   - **0 envs** → fail with: "Project has no environments. Create one (e.g. `Staging`) and add the referenced variables before generating."
   - **1 env** → use it silently, mention its name in the discovery snapshot. **Do NOT ask** — there's no choice to make.
   - **>1 envs** → `AskUserQuestion` listing environments (one option per env, with name + description). Never silently pick when there's a real choice.
3. **Verify keys exist:** `mcp__observo__list_variables(environment_id)` → build `{key → value}` map. For each collected placeholder, confirm presence. Missing keys → stop generation, list them, and suggest `mcp__observo__upsert_variables` to add them.
4. **Do not embed values into the spec.** Generation reads the values only to verify they exist + report what the test will pull at runtime. Runtime resolution is via the helper from step 5A.

### 3. Decide tier per test (only if the repo uses tiers)

If `TierTags` is non-empty (config or auto-discovery found tiers):

Tier vocabulary is **repo-specific**. The skill maps Observo case attributes to the repo's tiers using ordinal logic — config orders tiers safest→riskiest:

- Observo case `behavior == BEHAVIOR_DESTRUCTIVE` → **last** tier (riskiest).
- Case `steps[]` contains create/update/delete actions → **middle** tier (or last if only 2 tiers).
- All steps are reads (navigation + assertions, no submitted forms) → **first** tier (safest).
- When in doubt → second-from-first (avoid running mutations against prod).

If `TierTags` is empty (config explicitly skipped tiers, or auto-discovery found no tier vocabulary) — **don't emit a tier tag**. `@observo:<code>` is the only tag the test carries. Flag this in the summary so the user knows.

### 4. Map cases to files

- Default layout: one `.spec.ts` per Observo suite under `<SpecDir>/<suite-slug>.spec.ts` (or `<SpecDir>/<tier-folder>/<suite-slug>.spec.ts` if existing specs use tier-subfolders — auto-discover this pattern from `ExistingSpecPaths`).
- Slug = `kebab-case(suite_name)`.
- If a file with that path already exists → **extend it** (add `test(...)` block inside existing `test.describe`), don't overwrite.
- If a suite spans tiers (some reads + some writes) and the repo uses tier-subfolders → split into per-tier files.

### 5. Generate the test code

Each scenario → one `test(...)` block. Use whatever import paths and conventions auto-discovery found in `ExistingSpecPaths` — mirror the local style, don't impose one. Skeleton (adapt per discovery):

```typescript
import { test, expect } from '@playwright/test';
// + import from <SelectorsFile> if found
// + import from <FixturesDir> if a relevant fixture exists
// + import from <PagesDir> if a Page Object fits

test.describe('<Suite / Feature name>', () => {
  test(
    '<scenario — what is verified>',
    { tag: [<tier tag if applicable>, '@observo:<CODE>'] },
    async ({ page }) => {
      // Action / Data from case.steps[]
      await page.goto('/<route>');

      // Expected from case.steps[].expected — one assertion per step.
      // Selector style mirrors what auto-discovery found in existing specs.
    },
  );
});
```

**Rules — universal Playwright best practices (kept regardless of repo):**

1. **`@observo:<code>` tag** — hardcoded contract. Every test linked to an Observo case MUST carry one in the `tag: []` array. Reporter regex: `^@observo:([A-Z]+-\d+)$`. Do NOT use `test.info().annotations.push({...})` — that's an older pattern.
2. **Tier tag** — included only if `TierTagRequired=true` AND `TierTags` is non-empty. Otherwise omitted.
3. **Selectors** — only `getByTestId(...)`, `getByRole(...)`, `getByLabel(...)`. **Forbidden**: `nth-child`, raw CSS class selectors, XPath, fragile text matchers without role context.
4. **Waiting** — only `expect(...).toBeVisible()`, `page.waitForResponse()`, `page.waitForURL()`, `expect.poll(...)`. **Forbidden**: `page.waitForTimeout(N)`.
5. **No hardcoded credentials / URLs** — use env vars / fixtures discovered in step 1. For Observo `{{key}}` placeholders, route through the `vars.get(<key>)` helper from step 5A — never inline values, never plain `process.env.X` directly inside the spec.
6. **Atomic tests** — one scenario = one `test(...)`. Multi-step scenarios use `test.step(...)` blocks INSIDE one test, not multiple tests.
7. **No leaking state** — mutating tests must clean up (in `afterEach` or via fixture).

### 5A. Variables helper — `<utils_dir>/observo-vars.ts`

When any generated spec consumes `{{key}}` placeholders, ensure a helper module exists at `<utils_dir>/observo-vars.ts` (the directory of `selectors_file`, or `<playwright_root>/utils/` if no selectors file). **Scaffold on first use; never overwrite an existing one.**

**Per-key resolution contract — Observo MCP-source first, env fallback:**

1. Try `GET <API_BASE_URL>/api/projects/<OBSERVO_PROJECT_ID>/environments/<OBSERVO_ENV_ID>/variables/<key>` with `Authorization: Bearer <E2E_ACCOUNT_API_KEY>` — but **only** if `API_BASE_URL` and `E2E_ACCOUNT_API_KEY` are both set.
2. On HTTP 4xx/5xx, network error, or missing prerequisites → fall back to `process.env[envVarName(key)]` where `envVarName('regular_user_email')` returns `'E2E_REGULAR_USER_EMAIL'` (UPPER_SNAKE_CASE with `E2E_` prefix).
3. If both paths fail → throw with both attempted sources in the error message ("checked Observo `<env_name>` and `process.env.E2E_REGULAR_USER_EMAIL`").
4. Cache resolved values per-key per-process (don't re-fetch per assertion).

The helper reads `OBSERVO_PROJECT_ID` / `OBSERVO_ENV_ID` from env vars — **never hard-coded into the helper file**. The skill writes the resolved values into `<playwright_root>/.env.example` (project ID + env ID + one `E2E_<KEY>` placeholder per variable the spec consumes) so the user has a copy-paste template for `.env`.

**Generated specs consume via:**
```typescript
import { vars } from '@utils/observo-vars';
// ...
const email = await vars.get('regular_user_email');
const password = await vars.get('valid_password');
```

### 6. Page Object & selector registry (only if the repo uses them)

**Page Object policy:**
- If `PagesDir` is null → **skip POM**. Generate inline page interactions. Don't scaffold a POM just because the test does many actions — that's a repo-style decision, not ours.
- If `PagesDir` exists and a relevant `<Feature>Page.ts` is already there → import and use it.
- If `PagesDir` exists but the relevant Page Object doesn't, AND the test does >2-3 actions → scaffold `<PagesDir>/<Feature>Page.ts` mirroring the structure of an existing Page Object in `PagesDir` (read one as a reference). Flag the new file in the summary.

**Selectors registry policy:**
- If `SelectorsFile` is null → don't manage a registry. Use `data-testid="..."` inline strings or `getByRole(...)`. Don't invent a registry the repo doesn't have.
- If `SelectorsFile` exists and a needed testId is already there → use it.
- If `SelectorsFile` exists but the needed testId is missing → add it under the appropriate key, AND flag in the summary that the matching `data-testid="..."` attribute must be wired in the UI source (the skill writes the registry entry; the user wires JSX).

### 7. Fixtures & helpers

- If `ExistingFixtures` contains a fixture relevant to the test (auth, API seed, etc.) → import and use it, mirroring how existing specs use it.
- If no relevant fixture exists → use plain `import { test, expect } from '@playwright/test'`. **Don't auto-create new fixture files** — that's a bigger architectural decision; flag in summary that the user might want one.

### 8. Compile / list check before reporting done

After writing files, validate locally — from `PlaywrightRoot`:
```bash
cd <PlaywrightRoot>
npx tsc --noEmit                       # types (skip if no tsconfig.json present)
npx playwright test --list             # specs parse, tags syntactically valid
```

If `tsc` fails on generated code → fix before reporting success. If `--list` is missing `@observo:` tag → fix. Do NOT actually run the suite — that's `pw-run`'s job (or user runs it manually).

### 9. Don't touch `automation_status` at generation time

**Do NOT call `mcp__observo__update_test_case` to flip `automation_status` to `AUTOMATION_STATUS_AUTOMATED`**. Convention: flip happens only after a real green run pushes results back, AND it's an explicit human decision (not a side effect of `pw-run` either). Tell user to run the suite via `/pw-run` (or `cd <playwright_root> && make full` with the in-repo reporter), then explicitly mark cases as automated via natural-language ("mark OB-12..OB-49 as automated") if/when they decide.

### 10. Summary to user

Report after generation:
1. **Discovery snapshot** — what auto-discovery found (so the user can verify and create `.observo-pw.json` overrides if anything's off):
   ```
   Playwright root:   <path>
   Spec dir:          <path>
   POM:               <PagesDir | "not used in this repo">
   Selectors:         <SelectorsFile | "not used">
   Tier vocabulary:   [tag, ...] | "(none — tier tagging skipped)"
   Default Observo:   <code | "(asked / unset)">
   Environment:       <name> (single env, no question asked | picked from N)  ← only when spec consumes vars
   Variables in use:  [key1, key2, ...]                                        ← only when spec consumes vars
   ```
2. Source mode (Observo codes / PRD / inline) and what was processed.
3. Files written / extended (full paths).
4. **Selectors needing UI wiring** (only if `SelectorsFile` is in use) — explicit list of `data-testid` strings to add in the UI source.
4A. **Variables consumed at runtime** (only when spec uses `{{key}}` placeholders) — list of variable keys the spec will pull via `vars.get(...)`, the Observo environment they resolve from, and the env var names the helper falls back to (`E2E_<KEY>`). Show one line per variable so the user can populate `.env` if they need offline / no-API-key runs.
5. Skipped cases (already `AUTOMATED`, missing source data) — with reasons.
6. Compile/list check status.
7. **Suggested `.observo-pw.json` snippet** — if the user accepted asked-fallback values for tier vocabulary / project default / POM dir / etc. during this session, offer to write them to a `.observo-pw.json` config so future sessions skip the questions.
8. Next steps — exact commands using discovered paths. Default suggestion: `/pw-run` (sibling skill) — runs the suite and pushes results, including a coverage report. Or manual: `cd <PlaywrightRoot> && npx playwright test [--grep ...]`.

## Anti-patterns

- ❌ **Hardcoding ANY consumer-repo path or convention** — `e2e/`, `web-portal/tests/e2e/`, `OB`, `@prod-safe`, etc. All of these must come from discovery / config / ask. See D5 in `PRD-Playwright-Skills.md`.
- ❌ Using `test.info().annotations.push({type:'observo', description:'OB-X'})`. The reporter parses **tags** (regex `^@observo:([A-Z]+-\d+)$`), not annotations. Always use the `tag: []` form.
- ❌ Forcing a tier-tag on a test when the consumer repo doesn't use tiers (`TierTags` empty). Emit only `@observo:<code>` in that case.
- ❌ Putting create/update/delete actions in the "safest" tier tag's tests — that tag often runs against prod.
- ❌ `page.waitForTimeout(N)`. Always wait on an observable signal.
- ❌ `nth-child` / raw CSS class selectors / XPath. Use `data-testid` (via registry if present) or `getByRole`/`getByLabel`.
- ❌ Inventing a Page Object pattern that doesn't match the consumer repo's style. Read 1-2 existing Page Objects and mirror their shape.
- ❌ Creating a `.observo-pw.json` automatically without showing the user what would go in. Always offer the snippet first; let user confirm or paste manually.
- ❌ Flipping `automation_status` to `AUTOMATED` from this skill. Post-green-run only.
- ❌ Hardcoding credentials / URLs / API keys into generated specs — use env vars and fixtures.
- ❌ **Inlining values of Observo `{{key}}` placeholders into generated specs** (even into a "constants" block). Always go through the `vars.get(<key>)` helper from step 5A — that keeps Observo Variables as the single source of truth and lets the user swap environments without regenerating.
- ❌ **Silently picking an environment when the Observo project has >1.** Always `AskUserQuestion` in that case. Silent-pick is OK only when exactly one environment exists; mention "single env, no choice" in the discovery snapshot so the user understands no question was needed.
- ❌ Re-fetching the same Observo Variable per assertion. The helper must cache per-key per-process.
- ❌ Overwriting an existing spec file when an extend (new `test(...)` block) would do.
- ❌ Generating tests for Observo cases still in `STATUS_DRAFT` — they're not stable. Ask first.

## MCP tools used

- `mcp__observo__list_projects` — when default project isn't set; for asking the user to pick.
- `mcp__observo__list_test_cases` — resolve case codes → UUIDs / metadata; filter by status / automation_status / suite_id.
- `mcp__observo__get_test_case` — full case content with `steps[]`.
- `mcp__observo__list_suites` — for grouping cases into spec files by suite.
- `mcp__observo__list_environments` — resolve target environment when input cases reference `{{key}}` placeholders (silent if 1 env; ask if >1).
- `mcp__observo__list_variables` — verify referenced keys exist in the selected environment + report values the runtime helper will consume.

Read-only for this skill. No `update_test_case` / `update_case_in_run` / `create_run` / `upload_attachment` — those belong to the sibling `pw-run` skill (or are ad-hoc natural-language MCP calls).

## Defaults

- **Default Observo project:** none hardcoded. Resolution: `.observo-pw.json` → `list_projects` + ask → no default.
- **Default tier when ambiguous:** second tier from the start of `TierTags` (avoids prod-running mutations). If `TierTags` empty — no tier tag.
- **Default scope:** skip cases already `AUTOMATION_STATUS_AUTOMATED` unless explicit overwrite.
- **Default file layout:** one suite → one `.spec.ts` under discovered `SpecDir` (with tier-subfolders only if existing specs use that pattern).

## Handoff

After generation:
1. **Suggest creating `.observo-pw.json`** if discovery used asked-fallbacks during this session (it'll make next sessions zero-prompt).
2. **Run + writeback** — invoke `/pw-run` (sibling skill). It handles run resolution (`--run <key>` / sidecar `.observo-metadata.json` / `--create-run`), Playwright invocation, case/step writeback, attachments, and a coverage report. For ad-hoc run creation without running tests yet, use `/pw-run --create-run` (creates the run, doesn't execute Playwright).
3. **UI wiring** — if the summary listed missing `data-testid`s, hand off to whoever owns the UI source.
