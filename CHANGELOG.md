# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Extracted from observo monorepo as standalone repository (OB-260).
- MIT license, CHANGELOG, `.gitignore`.

### Notes

- v1.0.0 release ceremony tracked in OB-268. Until then this repo is considered
  pre-release (current `plugin.json:version` reflects the prior in-monorepo state).

## [0.8.0] - 2026-05-16

Last version released as part of the observo monorepo, before the standalone extraction.

### Added

- 7 skills: `prd`, `requirements-testing`, `observo-test-cases`,
  `observo-code-verifier`, `observo-review-test-case`, `pw-generate`, `pw-run`.
- 1 command: `pw-sync` (deprecated in favour of `pw-run`).
- Repo-agnostic Playwright integration via `@observo:<code>` tag contract.
- `pw-run` helper script for large attachment uploads.
