# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_No unreleased changes._

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
