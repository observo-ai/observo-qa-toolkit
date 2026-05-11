# observo-qa-toolkit

QA + product-spec toolkit для роботи з Observo. П'ять скілів, які покривають увесь цикл від сирого транскрипту мітингу до результатів Playwright тестів у платформі Observo.

Цей документ — практичний reference: **що кожен скіл робить, коли його тригерити, і в якій послідовності їх викликати**, щоб пройти повний цикл `PRD → test cases → код → ран → результати`.

---

## Зміст

- [Quick reference — який скіл під яку задачу](#quick-reference--який-скіл-під-яку-задачу)
- [End-to-end QA workflow](#end-to-end-qa-workflow)
- [Скіли в деталях](#скіли-в-деталях)
  - [1. `prd` — пишемо PRD з сирого input](#1-prd--пишемо-prd-з-сирого-input)
  - [2. `requirements-testing` — тестуємо самі вимоги](#2-requirements-testing--тестуємо-самі-вимоги)
  - [3. `observo-test-cases` — генеруємо кейси і пушимо в Observo](#3-observo-test-cases--генеруємо-кейси-і-пушимо-в-observo)
  - [4. `observo-code-verifier` — заземлюємо сценарії в код](#4-observo-code-verifier--заземлюємо-сценарії-в-код)
  - [5. `pw-sync` — Playwright ↔ Observo бридж](#5-pw-sync--playwright--observo-бридж)
- [Cheatsheet](#cheatsheet)

---

## Quick reference — який скіл під яку задачу

| Маю на руках… | Хочу отримати… | Скіл |
|---|---|---|
| транскрипт мітингу / нотатки / feature опис | структурований PRD | `prd` |
| PRD або requirements doc | список defects (ambiguity / gaps / conflicts) | `requirements-testing` |
| чистий PRD або requirements doc | кейси в Observo (IN_REVIEW, assigned to me) | `observo-test-cases` |
| драфт сценаріїв до пушу | сценарії, заземлені в реальний код (endpoint paths, error strings) | `observo-code-verifier` *(зазвичай авто-викликається з `observo-test-cases`)* |
| approved кейси в Observo | згенеровані Playwright `.spec.ts` файли | `/pw-sync import` |
| зелений (або червоний) ран Playwright | результати, аплоадженні в Observo run | `/pw-sync push` |
| анотовані Playwright тести | новий Observo run з потрібним `case_ids[]` | `/pw-sync run` |
| змішаний стан тестів і кейсів | звіт coverage gaps | `/pw-sync status` |
| тест змінився, Observo case не оновлено | синк code → Observo | `/pw-sync update` |

---

## End-to-end QA workflow

Повний цикл від нової ідеї фічі до результатів автотестів. Не кожен прохід проходить усі фази — пропускай ті, які не релевантні (наприклад, якщо PRD вже є, починай з фази 1).

### Phase 0 — PRD (`prd`)

**Тригер:** маєш transcript мітингу / brainstorm нотатки / опис фічі від PM, але немає структурованого doc'a.

**Що робиш:** `"напиши PRD з цих нотаток"` → скіл сам активується.

**На виході:**
- `knowledge-base/20 - Projects/<ProjectName>/PRD-<feature-name>.md` (за дефолтом)
- Структура: Overview / Problem / Goals / Non-Goals / User Stories / Data Model / API / UI / Integrations / Acceptance Criteria / Out of Scope
- Body в російській, заголовки в англійській

**Контрол:** прочитай AC секцію — це майбутній скелет тест-кейсів. Якщо AC слабкі — пиши краще зараз, ніж переробляти в Phase 2.

---

### Phase 1 — Requirements quality gate (`requirements-testing`)

**Тригер:** маєш PRD або як-built requirements doc, хочеш переконатися, що він testable, повний, без конфліктів — **перед** тим, як починати кодити чи писати тести.

**Що робиш:** `"перевір requirements у <шлях до файлу>"` або `"requirements testing for OB-123"`.

**Що скіл аналізує (5 осей):**
1. **Clarity** — vague "should/may", undefined terms, ambiguous pronouns
2. **Completeness** — negative paths, limits, errors, concurrency, security, access control
3. **Conflicts** — між різними requirements / тікетами
4. **Testability** — "fast", "user-friendly" без метрик
5. **Missing AC** — пропонує конкретні bullet points

**На виході:**
- Console: список defects по severity (blocker / major / minor) + цитати + suggested fixes
- Або: коментар на Jira тікеті (якщо в сесії підключений Jira-like MCP і ти назвав ключ тікета)
- Final block: proposed AC checklist для copy-paste

**Decision point:**
- **Blockers знайдено** → фікси requirements doc перед Phase 2
- **Тільки major/minor** → продовжуй у Phase 2, але тримай їх на радарі

---

### Phase 2 — Test case generation (`observo-test-cases` + `observo-code-verifier`)

**Тригер:** requirements чисті, час генерувати тест-кейси.

**Що робиш:** `"створи тест кейси для <feature> у Observo"`.

**Що відбувається всередині:**
1. Скіл читає source doc (типово `knowledge-base/04-Product/Requirements/<file>.md`)
2. *Optional* — викликає `requirements-testing` як quality gate (якщо AC слабкі)
3. Проектує сценарії з AC: happy / negative / boundaries / security / integration / idempotency
4. *Optional* — викликає `observo-code-verifier` для заземлення в код (endpoint paths, error strings, validation rules з `server/`)
5. Знаходить або створює Observo suite, робить **semantic duplicate check** проти існуючих кейсів у тому ж suite
6. Резолвить assignee (за дефолтом — твій Observo email, береться з memory)
7. Викликає `mcp__observo__bulk_create_test_cases` з batch усіх нових сценаріїв
8. **`status=IN_REVIEW`** за дефолтом — ти ревьюїш batch перед approve

**На виході:**
- N кейсів у вибраному project + suite
- Per-AC-block coverage table (бачиш одразу, що не покрито)
- Перелік fields, які MCP layer мовчки дропнув (відомий баг: `priority`/`type`/`behavior` у деяких build'ах)
- Active handoff: скіл сам запропонує "автоматизувати зараз?" — якщо так, делегує `pw-sync` або `senior-qa` scaffolding skill

**Decision point:**
- **Approve** в Observo UI (status → APPROVED) — це тригер для автоматизації
- **Залишити IN_REVIEW** — якщо потребує доробки

---

### Phase 3 — Generate Playwright specs (`/pw-sync import`)

**Тригер:** кейси в Observo APPROVED, час писати автотести.

**Що робиш:**

```
/pw-sync import --project OB --suite OB-AUTH
```

**Що відбувається:**
1. Скіл тягне всі `status=APPROVED` + `automation_status != AUTOMATED` кейси з suite
2. Для кожного — підбирає Playwright template (auth / checkout / search / forms / dashboard / settings / onboarding / accessibility / crud / api)
3. Генерує `.spec.ts` файли (один на suite), вшиває `test.info().annotations.push({ type: 'observo', description: 'OB-NNN' })`
4. **Не** перемикає `automation_status` на AUTOMATED — це станеться лише після зеленого ран

**На виході:**
- `tests/<suite-slug>.spec.ts` файли в репо
- Кожен тест має `observo` анотацію — це join key для майбутнього `push`

**Manual step:** допиши тіло тестів. Шаблон дає скелет (заголовки, locators, structure) — реальні `expect()` і `test.step()` ти прописуєш руками або делегуєш `engineering-skills:senior-qa`.

---

### Phase 4 — Run tests + push results (`/pw-sync run` + `/pw-sync push`)

**Тригер:** є анотовані Playwright тести, готовий до прогону.

#### 4a. Створити ран

```
/pw-sync run --project OB --name "Sprint 42 regression"
```

Скіл сам:
- Грепне репо за `type: 'observo'` анотаціями
- Збере усі унікальні короткі коди
- Резолвне в UUID через `list_test_cases`
- Викличе `create_run` з зібраним `case_ids[]`
- Поверне `RUN-XX` код

#### 4b. Прогнати тести

```bash
npx playwright test --reporter=json,html
```

`results.json` опиняється в `playwright-report/`.

#### 4c. Запушити результати

```
/pw-sync push --run RUN-42
```

Скіл сам:
- Прочитає `results.json` (свіжий — не перепрогонить)
- Для кожного тесту з `observo` анотацією → `update_case_in_run`
- Якщо `test.step()` 1:1 з Observo case steps → `update_step_in_run` по кроках
- Для FAILED/BLOCKED — аплоадить `trace.zip` / `screenshot.png` / `video.webm` через `upload_attachment`
- Не закриває ран автоматично (якщо ти не попросив явно)

**Status mapping:**

| Playwright | Observo |
|---|---|
| `passed` | `PASSED` |
| `passed` after retry | `PASSED` + коментар `Passed on retry N×` |
| `failed` | `FAILED` (з `error.message`) |
| `skipped` | `SKIPPED` |
| `interrupted` / `timedOut` | `BLOCKED` |

**На виході:** counts (pushed / passed / failed / skipped / blocked) + перелік **unlinked** тестів (без `observo` анотації) — це coverage gap.

---

### Phase 5 (опційно) — Health check + drift sync

#### `/pw-sync status` — раз на спринт

```
/pw-sync status --project OB
```

Чотири бакети:
- **Linked** — Observo case + Playwright тест (здорово)
- **Unautomated** — Observo case без тесту (плануй роботу)
- **Unlinked** — тест без Observo case (анотуй або створи кейс через `observo-test-cases`)
- **Stale** — анотація вказує на видалений код (cleanup)

#### `/pw-sync update` — після рефакторингу тесту

```
/pw-sync update --case OB-123
```

Витягне `test.step()` блоки → запише як `steps[]` в Observo case → флагне поля, які MCP дропнув (OB-243 / OB-244-style баги).

---

## Скіли в деталях

### 1. `prd` — пишемо PRD з сирого input

**Тригер-фрази:** `"напиши PRD"`, `"створи PRD"`, `"draft a PRD"`, `"PRD из транскрипта"`, або просто paste нотаток з очікуванням structured output.

**Inputs:** transcript мітингу, нотатки, опис фічі (текст).

**Outputs:** Markdown файл за шляхом `knowledge-base/20 - Projects/<ProjectName>/PRD-<feature-name>.md`.

**Особливості:**
- Body — російська, заголовки — англійська
- Кожне поле в Data Model має `Source` колонку (System / Pulled from <Entity> / Bot / Manual)
- Decisions з транскрипту фіксуються як decisions, не як suggestions
- Out of Scope (Future) явно перераховується — щоб не плодити scope creep

**Приклад:**

```
> Я: Маю transcript мітингу 2026-05-08 про email verification flow.
> Напиши PRD у knowledge-base/20 - Projects/Auth/.
```

---

### 2. `requirements-testing` — тестуємо самі вимоги

**Тригер-фрази:** `"тестуй рекваерменти"`, `"перевір PRD"`, `"review requirements"`, `"знайди дірки в PRD"`, `"check requirements quality"`, або просто Jira-key + `"що тут не так?"`.

**Inputs (хоча б одне):**
- Шлях до файлу (типово `knowledge-base/04-Product/Requirements/<file>.md` або `PRDs/<file>.md`)
- Jira ticket key (формат `[A-Z][A-Z0-9]+-\d+`)
- Inline text

**Outputs:**
- Якщо input — Jira ticket + Jira-like MCP підключений у сесії (будь-який tool з ім'ям типу `mcp__*jira*` / `mcp__*atlassian*`) → comment на тікет з ADF форматом
- Інакше — console list з 🟥/🟧/🟨 severity badges

**Що це НЕ робить:**
- Не генерує тест-кейси (це `observo-test-cases`)
- Не переписує doc цілком — лише point fixes
- Не паравафрує цитати — завжди буквальний quote з source

**Приклад:**

```
> Я: requirements testing for knowledge-base/04-Product/Requirements/01-Auth-Accounts.md
```

На виході:
```
🟥 Blockers (2)
  D-1 · conflict · Section "Password reset"
  Quote: "Reset link valid 15 minutes"
  Issue: суперечить Section "Token expiry" → "Reset link valid 1 hour"
  Fix: Узгодити в один TTL...
  ...

🟧 Major (3)
  ...

## Proposed acceptance criteria
- [ ] Reset link expires exactly 15 minutes after generation
- [ ] ...
```

---

### 3. `observo-test-cases` — генеруємо кейси і пушимо в Observo

**Тригер-фрази:** `"створи тест кейси для <X>"`, `"напиши test cases на <module>"`, `"push test cases to Observo"`.

**Inputs:**
- Source doc — найчастіше `knowledge-base/04-Product/Requirements/<file>.md`
- Optional: explicit project / suite, status, assignee

**Outputs:**
- N test cases в Observo (default project = `OB`, suite — за модулем)
- Default status = `IN_REVIEW`
- Default assignee = current user (з memory: `blake.y@globalit.systems` для цього репо)
- Per-AC coverage table + flagged dropped fields

**Disambiguation:** якщо ти НЕ сказав явно "Observo records" — скіл спитає одне питання: Observo records чи local test code (Jest/Playwright/Vitest). Це захист від випадкового spam'у в платформу.

**Quality gates (опціональні, авто):**
- Якщо `requirements-testing` доступний і doc має слабкий AC → авто-викликає його
- Перед push'ем → авто-викликає `observo-code-verifier` (якщо є filesystem access)

**Active handoff:** після створення кейсів скіл запропонує "автоматизувати зараз?" — якщо так, делегує до `pw-sync` або scaffolding skill.

**Приклад:**

```
> Я: створи тест кейси для knowledge-base/04-Product/Requirements/01-Auth-Accounts.md
> Скіл: Це Observo records чи Jest код? → ти: Observo
> Скіл: Status? → ти: IN_REVIEW
> [тягне doc, проектує сценарії, верифікує проти server/, пушить batch]
> Скіл: Створено 47 кейсів у suite OB-AUTH. Автоматизувати зараз? → ти: Yes
> [делегує до /pw-sync import]
```

---

### 4. `observo-code-verifier` — заземлюємо сценарії в код

**Тригер-фрази:** `"verify test cases against code"`, `"ground these scenarios in implementation"`, `"check error messages match the code"`. Зазвичай — авто-виклик з `observo-test-cases`.

**Inputs:** draft scenario list (name + code-checkable claims: endpoint paths, error strings, validation rules).

**Outputs:** анотований список з статусами (`ok` / `string-drift` / `endpoint-mismatch` / `missing` / `skipped`) + `suggested_corrections` з `was` / `now` / `evidence:file:line`.

**Особливості:**
- **Graceful degradation** — якщо немає filesystem access, повертає сценарії without змін, прапорить `skipped`
- **Read-only** — не редагує код, навіть якщо побачить баги в handler'ах
- **Grep > Read** — не читає цілі файли, де grep вистачить
- **Доказова база** — кожен `evidence` має бути реальний `file:line`, не fabricated

**Decision policy в `observo-test-cases` після верифікації:**

| Status | Дія |
|---|---|
| `ok` | без змін |
| `string-drift` | apply correction silently (це literal fact з коду) |
| `endpoint-mismatch` | ask once — use suggestion чи drop scenario |
| `missing` | keep scenario, flag в summary |
| `skipped` | proceed, flag що verification skipped |

---

### 5. `pw-sync` — Playwright ↔ Observo бридж

П'ять capabilities, всі через `/pw-sync <subcommand>`. Деталі — у попередньому розділі (Phase 3 і 4).

| Subcommand | Призначення |
|---|---|
| `/pw-sync import --project --suite` | Observo APPROVED cases → Playwright `.spec.ts` шаблони |
| `/pw-sync run --project --name` | Грепне репо за анотаціями → створить новий Observo run |
| `/pw-sync push --run` | Playwright `results.json` → Observo run (case + step level, з attachments на failure) |
| `/pw-sync status --project [--suite]` | Coverage gap report (Linked / Unautomated / Unlinked / Stale) |
| `/pw-sync update --case` | Playwright `test.step()` → Observo case `steps[]` (drift sync) |

**Join key:** `test.info().annotations.push({ type: 'observo', description: 'OB-NNN' })` — без анотації тест "невидимий" для всіх `/pw-sync` команд.

**Prerequisite:** `observo` MCP сервер підключений (вже є — `mcp.observoai.co`).

---

## Cheatsheet

```
# Phase 0: Сирий input → PRD
"напиши PRD з цих нотаток"                      [skill: prd]

# Phase 1: Перевірка вимог
"перевір requirements у <path>"                 [skill: requirements-testing]

# Phase 2: Генерація кейсів
"створи тест кейси для <path>"                  [skill: observo-test-cases]
  └─ auto: observo-code-verifier (якщо доступний)
  └─ auto: requirements-testing (якщо AC слабкі)

# Approve в Observo UI                          [manual]

# Phase 3: Генерація Playwright specs
/pw-sync import --project OB --suite OB-AUTH

# Phase 4: Run + push
/pw-sync run --project OB --name "..."
npx playwright test --reporter=json,html
/pw-sync push --run RUN-42

# Phase 5: Health checks
/pw-sync status --project OB
/pw-sync update --case OB-123
```

---

## Тригери в одному списку

Якщо забув назву скіла — просто пиши naturally, description-matching сам активує:

- `"напиши PRD"` → `prd`
- `"перевір PRD"`, `"тестуй рекваерменти"`, `"знайди дірки"` → `requirements-testing`
- `"створи тест кейси"`, `"push test cases to Observo"` → `observo-test-cases`
- `"verify against code"`, `"ground in implementation"` → `observo-code-verifier`
- `"запушити результати в Observo"`, `"створити ран в Observo"` → `pw-sync` (або прямо `/pw-sync <subcommand>`)
