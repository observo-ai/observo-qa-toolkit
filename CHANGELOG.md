# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_No unreleased changes._

## [1.1.2] - 2026-05-17

### Documentation

- **TELEMETRY.md updated for two new Layer 1 signals shipped server-side
  on the hosted MCP (`mcp.observoai.co`):**
  - **`unknown_tool_invoke` event_type (OB-275).** When a client names a
    tool that does not exist on the server, the request is rejected by
    the SDK with a `Method not found` JSON-RPC error AND independently
    recorded as an `unknown_tool_invoke` row. This is product-demand
    data: the client already translated a human prompt into a concrete
    tool name, so the row tells us which capabilities people reach for.
    Privacy posture identical to `tool_invoke` — only the requested
    name is captured.
  - **`arg_schema` field (OB-276).** Each successful `tool_invoke` row
    now also records a schema-only sampling of the tool's argument
    shape:
    ```json
    {"present_fields": ["name", "severity"], "field_sizes": {"name": 5, "severity": 6}}
    ```
    Field NAMES + JSON-byte SIZES of values, never the values
    themselves. Top-level keys only (nested objects are not recursed).
    Capped at 4 KiB end-to-end; oversized payloads produce `arg_schema = null`
    rather than failing the call.

Both signals are transparent to plugin consumers — no code change is
required to opt in or out. The same Layer 1 "hosted-side telemetry is on
for every account using `mcp.observoai.co`" semantic continues to apply.
If your compliance posture requires no telemetry, file an issue.

## [1.1.1] - 2026-05-17

### Fixed

- **`observo-toolkit-bootstrap` plugin-version lookup (OB-278).** The skill
  was missing the canonical marketplace-cache path
  (`~/.claude/plugins/cache/<marketplace>/observo-qa-toolkit/<version>/`),
  so when a consumer ran `/plugin update` while also having an older
  vendored / submodule copy on disk, the beacon mis-reported the stale
  version. The lookup list is now reordered cache-first, with version-sort
  semantics (`sort -V`) over the cached versioned directories. Submodule
  / vendored paths remain valid but are last because they often lag the
  user's actual runtime version.

### Documentation

- TELEMETRY.md `plugin_version` field row now spells out the resolution
  order, so the disclosure matches what the skill actually does.

## [1.1.0] - 2026-05-17

### Added

- **`observo-toolkit-bootstrap` skill** — records one Layer 2 `plugin_install`
  telemetry beacon per consumer repo, idempotently. Gated on
  `.observo-toolkit.json:telemetry_enabled` (opt-in, default `false`).
  Writes a marker at `.observo-toolkit/.install-seeded` so subsequent
  invocations are a no-op; re-fires automatically when the plugin version
  in `.claude-plugin/plugin.json` changes. Auto-writes a nested
  `.observo-toolkit/.gitignore` so the marker never gets committed by
  accident.

### Changed

- `plugin.json` description now lists eight skills (was seven).

## [1.0.0] - 2026-05-17

Initial public release. Plugin extracted from the observo monorepo, refactored
for public consumption, and distributed through the `observo-ai-plugins`
marketplace and (pending acceptance) `claude-plugins-official`.

### Added

- **Standalone repository** at `observo-ai/observo-qa-toolkit` with MIT license,
  CHANGELOG, `.gitignore` (OB-260).
- **`.observo-toolkit.json` config schema** (`.observo-toolkit.example.json` in
  repo root). 17 optional fields covering PRD save dir, language defaults,
  requirements dir, default Observo project + assignee, Playwright discovery
  overrides, and an opt-in telemetry flag (OB-262).
- **Plugin CI workflow** with 3 jobs: markdownlint (relaxed prose-friendly
  config), anti-coupling grep (no host paths, no Cyrillic in skills/+commands/),
  manifest-validate (plugin.json schema + per-skill frontmatter + JSONC config
  validity) (OB-265).
- **Distribution via own marketplace** `observo-ai/claude-plugins`:
  `/plugin marketplace add observo-ai/claude-plugins` +
  `/plugin install observo-qa-toolkit@observo-ai-plugins` (OB-266).

### Changed

- **Repo-agnostic refactor.** All references to host-specific paths
  (`kb-observo/`), accounts, and identities removed from `skills/`, `commands/`,
  and `README.md`. Plugin works on any Playwright project (OB-261).
- **Strict English-only** in `skills/` and `commands/` — body prose, trigger
  examples, and frontmatter are English. Multilingual support is now a
  config-layer concern (`prd_language`), not hardcoded skill content (OB-261).
- **README rewritten** for external cold-start onboarding — primary install is
  `/plugin install`, git clone is documented as advanced fallback only.
  ≤5-minute cold-onboarding target (OB-263).

### Removed

- Internal-only references to `kb-observo/` paths.
- Self-hosted MCP server documentation — hosted-only (`mcp.observoai.co`).
- Russian PRD template body (replaced with English; opt-in via config).

## [0.8.0] - 2026-05-16

Last version released as part of the observo monorepo, before the standalone extraction.

### Added

- 7 skills: `prd`, `requirements-testing`, `observo-test-cases`,
  `observo-code-verifier`, `observo-review-test-case`, `pw-generate`, `pw-run`.
- 1 command: `pw-sync` (deprecated in favour of `pw-run`).
- Repo-agnostic Playwright integration via `@observo:<code>` tag contract.
- `pw-run` helper script for large attachment uploads.
