# observo-qa-toolkit

QA + product-spec toolkit для роботи з Observo (`https://observoai.co`). **Сім скілів**, що покривають весь цикл від сирого транскрипту мітингу до результатів Playwright тестів у платформі Observo.

Цей документ — практичний reference: **що кожен скіл робить, коли його тригерити, в якій послідовності їх викликати**, щоб пройти повний цикл `PRD → test cases → review → код → ран → результати`.

> **Repo-agnostic.** Скіли `pw-generate` і `pw-run` працюють на будь-якому Playwright-проекті. Конкретні шляхи (spec dir, Page Object pattern, tier-теги, дефолтний Observo project) консумерський репо ставить у `.observo-pw.json` у корені, або скіли авто-дискаверять. Єдиний hardcoded contract — `@observo:<code>` tag, через нього reporter і MCP лінкують Playwright тест із Observo case.

---

## Зміст

- [Quick reference — який скіл під яку задачу](#quick-reference--який-скіл-під-яку-задачу)
- [End-to-end QA workflow](#end-to-end-qa-workflow)
- [Decision tree — intent → skill / mechanism](#decision-tree--intent--skill--mechanism)
- [Скіли в деталях](#скіли-в-деталях)
- [Cheatsheet](#cheatsheet)
- [Тригери в одному списку](#тригери-в-одному-списку)

---

## Quick reference — який скіл під яку задачу

| Маю на руках… | Хочу отримати… | Скіл |
|---|---|---|
| транскрипт мітингу / нотатки / feature опис | структурований PRD | `prd` |
| PRD або requirements doc | список defects (ambiguity / gaps / conflicts) | `requirements-testing` |
| чистий PRD або requirements doc | кейси в Observo (IN_REVIEW, assigned to me) | `observo-test-cases` |
| драфт сценаріїв до пушу | сценарії, заземлені в реальний код (endpoint paths, error strings) | `observo-code-verifier` *(auto-callout з `observo-test-cases`)* |
| свіжо створені кейси в Observo | review проти 15-criteria checklist + per-issue comments | `observo-review-test-case` |
| approved кейси в Observo або PRD | згенеровані Playwright `.spec.ts` файли | `pw-generate` |
| готові Playwright тести | прогон + writeback в Observo (case/step status, attachments, run-level event-log) | `pw-run` |
| Playwright crash mid-flight, є свіжий `results.json` | re-push без повторного запуску | `pw-run --reuse-results --run <key>` |
| просто хочу побачити coverage gaps | 4-bucket звіт (Linked / Unautomated / Unlinked / Stale) | `pw-run` (емітить завжди в summary) |

---

## End-to-end QA workflow

Повний цикл від нової ідеї фічі до результатів автотестів. Не кожен прохід проходить усі фази — пропускай ті, які не релевантні.

### Phase 0 — PRD (`prd`)

**Тригер:** маєш transcript мітингу / brainstorm нотатки / опис фічі від PM, але немає структурованого doc'a.

**Що робиш:** `"напиши PRD з цих нотаток"`.

**На виході:** Markdown файл (для observo репо — `knowledge-base/04-Product/PRDs/`), body російська + заголовки англійська, секції Overview / Problem / Goals / Non-Goals / User Stories / Data Model / API / UI / Integrations / Acceptance Criteria / Out of Scope.

**Контрол:** прочитай AC секцію — це майбутній скелет тест-кейсів.

---

### Phase 1 — Requirements quality gate (`requirements-testing`)

**Тригер:** маєш PRD/requirements doc, хочеш переконатися що він testable + повний + без конфліктів.

**Що робиш:** `"перевір requirements у <шлях до файлу>"` або `"requirements testing for OB-123"`.

**Що скіл аналізує (5 осей):** Clarity, Completeness, Conflicts, Testability, Missing AC.

**На виході:** console list defects по severity + цитати з source + suggested fixes. Якщо Jira-MCP підключений — постить як comment на тікет.

**Decision point:** Blockers → фікс перед Phase 2; major/minor → continue.

---

### Phase 2 — Test case generation (`observo-test-cases` + `observo-code-verifier`)

**Тригер:** requirements чисті, час генерувати тест-кейси.

**Що робиш:** `"створи тест кейси для <feature> у Observo"`.

**Що відбувається:**
1. Скіл читає source doc.
2. *Optional auto* — викликає `requirements-testing` як quality gate (якщо AC слабкі).
3. Проектує сценарії з AC: happy / negative / boundaries / security / integration / idempotency.
4. *Optional auto* — викликає `observo-code-verifier` для заземлення в код (якщо є filesystem access).
5. Знаходить/створює Observo suite, робить **semantic duplicate check**.
6. Резолвить assignee (з memory або питає).
7. `mcp__observo__bulk_create_test_cases` — batch усіх нових сценаріїв.
8. Default `status=IN_REVIEW`.

**Active handoff:** скіл сам пропонує "автоматизувати зараз?" — групує кейси per `layer` (E2E / API / UNIT / etc.) і пропонує preferred scaffolder для кожної групи (`pw-generate` для E2E, `api-test-suite-builder` для API, `senior-qa` для UNIT тощо).

---

### Phase 3 — Review test cases (`observo-review-test-case`)

**Тригер:** маєш свіжо створені кейси у Observo (статус IN_REVIEW), хочеш systematic quality pass перед approve.

**Що робиш:** `"review test case OB-12"` або `"відревьюй кейс <code>"` або `"score test cases у suite OB-AUTH"`.

**Що відбувається:**
1. Прогоняє кейс через 15-criteria quality checklist (title, atomicity, executable steps, expected result, scope tagging, etc.).
2. Постить per-issue review comments через MCP у правильному scope (`CASE` / `FIELD` / `STEP`).
3. Призначає compact 0–10 score.
4. Якщо коментарі були створені — перемикає статус на `STATUS_CHANGES_REQUESTED`.

**Не робить:** не редагує сам кейс, не resolve-ить коментарі, не approve-ить — це людські рішення.

---

### Phase 4 — Generate Playwright specs (`pw-generate`)

**Тригер:** кейси в Observo `APPROVED` (або PRD доступний для direct-from-PRD mode), час писати автотести.

**Що робиш:**
```
generate Playwright tests for OB-12..OB-49
```
або
```
згенеруй .spec.ts з knowledge-base/04-Product/Requirements/01-Auth.md
```

**Що відбувається:**
1. Discovery — читає `.observo-pw.json` + auto-detect Playwright config / spec dir / Page Object pattern / selectors registry / fixtures / tier vocabulary.
2. Resolve source — Observo case codes (Mode A) або PRD doc (Mode B) або inline опис (Mode C). Disambiguation якщо неясно (Playwright code vs. Observo records).
3. Генерує `.spec.ts` файли — кожен тест має `@observo:<code>` tag + tier tag (якщо репо їх використовує). Селектори — `data-testid` / `getByRole`, заборона `waitForTimeout`.
4. Scaffolить Page Object і додає TestIds до selectors registry — **тільки** якщо репо ці patterns використовує.
5. Запускає `tsc --noEmit` + `playwright test --list` перед reporting "done".

**Не флапає** `automation_status` на `AUTOMATED` — це відбудеться лише після зеленого ран через Phase 5.

**На виході:** список згенерованих файлів + discovery snapshot + selectors що потребують UI wiring + suggested `.observo-pw.json` snippet (якщо discovery використало fallback-and).

---

### Phase 5 — Run + writeback + coverage (`pw-run`)

**Тригер:** готовий до прогону + хочеш результати в Observo.

**Що робиш (CI / regular):**
```
/pw-run --grep "@prod-safe"
```

**Що робиш (re-push після crash):**
```
/pw-run --reuse-results --run RUN-42
```

**Що робиш (для CI з coverage-gate):**
```
/pw-run --fail-on-coverage-gap
```

**Що відбувається:**
1. Discovery — той самий `.observo-pw.json` контракт що pw-generate.
2. **За дефолтом** — запускає `npx playwright test --reporter=json,html,list`. `--reuse-results` opt-in для skip rerun.
3. Resolve target Observo run: `--run <key>` → sidecar `.observo-metadata.json.runKey` (написаний in-repo `observo-reporter.ts` у `onBegin`) → `--create-run` → fail.
4. **Reporter coexistence detection** — якщо sidecar exists AND `OBSERVO_REPORTER_ENABLED=true`, reporter уже все запушив; skip duplicate work, робити **тільки** coverage + summary.
5. Інакше — повний writeback: per-case status + comment, per-step status (коли Playwright step count == Observo case step count), case-level attachments на FAILED/BLOCKED, run-level `results.json` як event log (завжди).
6. **Coverage report завжди** — 4 buckets (Linked / Unautomated / Unlinked / Stale).
7. `--fail-on-coverage-gap` (opt-in) → exit 2 якщо `Unautomated > 0 || Stale > 0`.
8. Finalize run unless `--keep-open`.

**Status mapping** (узгоджено між pw-run і in-repo reporter):

| Playwright | Observo |
|---|---|
| `passed` | `passed` |
| `passed` after retry | `passed` + comment `Passed on retry Nx` |
| `failed` | `failed` (з error.message + stack) |
| `skipped` | `skipped` |
| `timedOut` / `interrupted` | `blocked` |

---

### CI flow alternative

Якщо консумерський репо вже має in-repo reporter (`e2e/reporters/observo-reporter.ts` для observo) і CI запускає `make full` / `npx playwright test` напряму:

1. Reporter сам у `onBegin` створює Observo run і пише sidecar `.observo-metadata.json` у `playwright-report/`.
2. Reporter сам у `onTestEnd` пушить per-case + per-step + attachments на FAILED.
3. Reporter сам у `onEnd` пушить run-level `results.json` і finalize-ить run.
4. **`pw-run` — як fallback step:** запустити `pw-run --reuse-results` тільки коли reporter не закінчив (crash mid-flight). Скіл детектить sidecar і coexistence-режим — додає **тільки** coverage report + summary. Без duplicate writes.

Це дає zero-overhead CI: reporter inline пише все, `pw-run` лише як safety net + coverage gate.

---

## Decision tree — intent → skill / mechanism

| Хочу… | Як |
|---|---|
| згенерувати spec файли | `pw-generate` |
| run + push results | `/pw-run` (default — запускає + пушить) |
| створити run без запуску | `/pw-run --create-run` |
| re-push після crash | `/pw-run --reuse-results --run <key>` |
| лише coverage report (без writeback) | у summary будь-якого `/pw-run` виклику |
| CI fail-fast на coverage gap | `/pw-run --fail-on-coverage-gap` |
| оновити Observo case з коду | natural-language → `mcp__observo__update_test_case` напряму (rarely-used, без окремого скіла) |
| ad-hoc delete | natural-language з explicit confirmation, MCP delete tool вручну |

---

## Скіли в деталях

### 1. `prd` — пишемо PRD з сирого input

**Тригер-фрази:** `"напиши PRD"`, `"створи PRD"`, `"draft a PRD"`, `"PRD из транскрипта"`.

**Inputs:** transcript мітингу, нотатки, опис фічі (текст).

**Outputs:** Markdown файл. Body — російська, заголовки — англійська. Кожне поле в Data Model має `Source` колонку. Decisions з транскрипту фіксуються як decisions, не suggestions. Out of Scope явно перераховується.

---

### 2. `requirements-testing` — тестуємо самі вимоги

**Тригер-фрази:** `"перевір PRD"`, `"review requirements"`, `"знайди дірки в PRD"`, Jira-key + `"що тут не так?"`.

**Inputs:** шлях до файлу, Jira ticket key, або inline text.

**Outputs:** console list defects з severity badges (🟥/🟧/🟨) + цитати + suggested fixes. Або Jira comment (якщо Jira-MCP підключений).

**Не робить:** не генерує кейси, не переписує doc, не парафразує цитати — буквальний quote з source.

---

### 3. `observo-test-cases` — генеруємо кейси і пушимо в Observo

**Тригер-фрази:** `"створи тест кейси для <X>"`, `"push test cases to Observo"`.

**Outputs:** N test cases в Observo. Default `status=IN_REVIEW`, default assignee = current user. Per-AC coverage table + flagged dropped fields.

**Disambiguation:** якщо ти НЕ сказав явно "Observo records" — скіл спитає одне питання: Observo records чи local test code.

**Quality gates (auto):** `requirements-testing` (якщо AC слабкі) + `observo-code-verifier` (якщо filesystem access).

**Active handoff:** після створення скіл групує кейси per `layer` і пропонує scaffolder per group (`pw-generate` для E2E, `api-test-suite-builder` для API, `senior-qa` для UNIT, тощо).

---

### 4. `observo-code-verifier` — заземлюємо сценарії в код

**Тригер-фрази:** `"verify test cases against code"`, `"ground these scenarios in implementation"`. Зазвичай — auto-callout з `observo-test-cases`.

**Inputs:** draft scenario list (name + code-checkable claims: endpoint paths, error strings, validation rules).

**Outputs:** анотований список зі статусами (`ok` / `string-drift` / `endpoint-mismatch` / `missing` / `skipped`) + `suggested_corrections` з `was` / `now` / `evidence:file:line`.

**Особливості:** graceful degradation коли немає filesystem access, read-only (не редагує код), grep > Read, evidence завжди реальний `file:line`.

---

### 5. `observo-review-test-case` — review якості створених кейсів

**Тригер-фрази:** `"review test case OB-12"`, `"відревьюй кейс <code>"`, `"score test cases у suite OB-AUTH"`.

**Inputs:** один або кілька test-case short codes / UUID.

**Outputs:**
- Per-issue review comments в Observo з правильним scope (`CASE` / `FIELD` / `STEP`).
- Compact 0–10 score.
- Перемикає `status` → `STATUS_CHANGES_REQUESTED` коли коментарі були створені.

**15-criteria checklist:** title quality, atomicity, executable steps, expected result явний, scope tagging, тощо.

**Не робить:** не редагує сам кейс, не resolve-ить коментарі, не approve-ить (людські рішення).

---

### 6. `pw-generate` — repo-agnostic Playwright spec generator

**Тригер-фрази:** `"generate Playwright tests for OB-X"`, `"автоматизуй кейс E2E-007 на Playwright"`, `"convert these Observo cases to Playwright"`.

**Inputs (3 modes):**
- **A:** Observo case codes (e.g. `OB-12..OB-49`) — pulled via `get_test_case`.
- **B:** PRD/requirements doc path.
- **C:** Inline опис фічі.

**Repo discovery (D5 contract):** `.observo-pw.json` → auto-detect `playwright.config.*` + `pages/` + `selectors.ts` + `fixtures/` → AskUserQuestion fallback. Hardcoded — лише `@observo:<code>` tag і MCP tool names.

**`.observo-pw.json` schema (всі поля optional):**

```jsonc
{
  "playwright_root": "e2e",
  "spec_dir": "e2e/tests",
  "pages_dir": "e2e/pages",                   // null/absent → POM not used
  "selectors_file": "e2e/utils/selectors.ts",
  "selectors_export": "TestIds",
  "fixtures_dir": "e2e/fixtures",
  "tier_tags": ["@prod-safe", "@full-stack", "@destructive"],
  "tier_tag_required": true,                  // false → skip tier tagging
  "default_observo_project": "OB",
  "reporter_path": "e2e/reporters/observo-reporter.ts",
  "metadata_file": "e2e/playwright-report/.observo-metadata.json"
}
```

**Universal rules (enforced regardless of repo):**
1. `@observo:<code>` tag на кожному тесті (regex `^@observo:([A-Z]+-\d+)$`).
2. Tier tag — якщо репо їх має (config / discovery).
3. Селектори: `getByTestId(...)` / `getByRole(...)` / `getByLabel(...)`. Заборона `nth-child` / raw CSS / XPath.
4. Очікування: `expect(...).toBeVisible()` / `waitForResponse()` / `waitForURL()` / `expect.poll(...)`. **Заборона `waitForTimeout(N)`**.
5. Atomic tests — одна сценарія = один `test(...)`.
6. Без hardcoded credentials / URLs.

**Не флапає** `automation_status` — це окреме рішення user-а post-green-run.

---

### 7. `pw-run` — runner + Observo writeback + coverage gate

**Тригер-фрази:** `"запусти тести і запиши в Observo"`, `"/pw-run"`, `"re-push the last run after crash"`.

**CLI flags:**

| Flag | Default | Effect |
|---|---|---|
| `--run <key>` | (unset) | Use this exact run key (e.g. `RUN-42`). Highest priority. |
| `--create-run` | false | Create a new Observo run via `mcp__observo__create_run`. |
| `--project <code>` | from config | Override `default_observo_project`. |
| `--grep <pattern>` | (unset) | Forwarded to `playwright test --grep`. |
| `--reuse-results` | false | Skip Playwright run, parse existing `results.json`. |
| `--keep-open` | false | Don't finalize the run (partial push scenario). |
| `--fail-on-coverage-gap` | false | Exit 2 if `Unautomated > 0 || Stale > 0`. CI gate. |

**Run resolution priority:** `--run <key>` → sidecar `.observo-metadata.json.runKey` → `--create-run` → fail.

**Reporter coexistence:** якщо sidecar exists + `OBSERVO_REPORTER_ENABLED=true` → reporter уже зробив writeback; skill робить **тільки** coverage + summary.

**Attachment policy:**
- **Case-level (FAILED/BLOCKED only):** screenshot.png / trace.zip / video.webm → `upload_attachment` scope=run_case.
- **Run-level (always):** full `results.json` → `upload_attachment` scope=run. Це event log для ontology (PRD-Playwright-Skills.md D2).
- **HTML report не пушимо** — людський артефакт, дублює `results.json` для машин.

**Coverage report завжди** у summary — 4 buckets (Linked / Unautomated / Unlinked / Stale).

---

## Cheatsheet

```
# Phase 0: Сирий input → PRD
"напиши PRD з цих нотаток"                        [skill: prd]

# Phase 1: Перевірка вимог
"перевір requirements у <path>"                   [skill: requirements-testing]

# Phase 2: Генерація кейсів
"створи тест кейси для <path>"                    [skill: observo-test-cases]
  └─ auto: observo-code-verifier (якщо доступний)
  └─ auto: requirements-testing (якщо AC слабкі)

# Phase 3: Review кейсів
"review test case OB-12"                          [skill: observo-review-test-case]
"score test cases у suite OB-AUTH"                [skill: observo-review-test-case]

# Approve в Observo UI                            [manual]

# Phase 4: Генерація Playwright specs
"generate Playwright tests for OB-12..OB-49"      [skill: pw-generate]
"згенеруй .spec.ts з <PRD path>"                  [skill: pw-generate]

# Phase 5: Run + writeback + coverage
/pw-run                                            # default: run + push
/pw-run --grep "@prod-safe"                        # filter tests
/pw-run --reuse-results --run RUN-42               # re-push crash recovery
/pw-run --create-run                               # standalone create run
/pw-run --fail-on-coverage-gap                     # CI gate

# CI alternative (reporter inline + pw-run as fallback)
OBSERVO_REPORTER_ENABLED=true cd e2e && make full  # reporter does writeback
/pw-run --reuse-results                            # fallback if reporter crashed
```

---

## Тригери в одному списку

Якщо забув назву скіла — просто пиши naturally, description-matching сам активує:

- `"напиши PRD"` → `prd`
- `"перевір PRD"`, `"тестуй рекваерменти"`, `"знайди дірки"` → `requirements-testing`
- `"створи тест кейси"`, `"push test cases to Observo"` → `observo-test-cases`
- `"verify against code"`, `"ground in implementation"` → `observo-code-verifier`
- `"review test case"`, `"score test cases"`, `"відревьюй кейс"` → `observo-review-test-case`
- `"generate Playwright tests"`, `"автоматизуй кейс на Playwright"`, `"згенеруй .spec.ts"` → `pw-generate`
- `"запусти тести"`, `"run e2e and push results"`, `"/pw-run"`, `"re-push the last run"` → `pw-run`

---

## Prerequisites

- **`observo` MCP сервер** підключений у сесії — інструменти видні як `mcp__observo__*`. Без нього `observo-test-cases`, `observo-review-test-case`, `pw-generate` (Mode A) і `pw-run` не працюють.
- **Playwright** встановлений у консумерському репо (з `playwright.config.ts` де-небудь). Для свіжого репо без Playwright — спершу `npm create playwright@latest`.
- **`OBSERVO_REPORTER_ENABLED=true`** у CI env — для активного writeback з in-repo reporter (опціонально; без нього `pw-run` справляється сам).
