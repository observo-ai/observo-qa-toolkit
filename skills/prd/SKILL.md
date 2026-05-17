---
name: prd
description: Write a structured PRD from raw user input — meeting transcripts, notes, or feature descriptions. Default English body and English section headings; non-English body opt-in via `.observo-toolkit.json:prd_language`. Use when the user asks to "write a PRD", "draft a PRD", "write a PRD for <feature>", "PRD from this transcript / these notes", or provides meeting notes / requirements text expecting a structured product spec back. Default save location: `<prd_save_dir>` from `.observo-toolkit.json`, fallback `./docs/PRDs/<feature-name>.md`.
---

# PRD Skill — Write a PRD from user input

The user will provide raw input — typically a meeting transcript, notes, or a brief description of a feature. Your job is to produce a structured PRD.

**Language: English by default.** Body, section headings, field notes, and user stories are all English. If the consumer repo opts into a different body language via `.observo-toolkit.json:prd_language` (`ru` / `ua` / etc.), keep the section headings English regardless — code identifiers (field names, endpoints) always stay English.

## Steps

1. Read everything the user provides. If it's a meeting transcript, extract decisions, requirements, field names, data sources, and explicit non-goals.
2. Ask no clarifying questions unless a critical piece is truly missing (e.g. no target product mentioned at all). Make reasonable assumptions and note them.
3. Write the PRD using the structure below. Body language: read `.observo-toolkit.json:prd_language` — default English; respect the configured value if set.
4. Save the file to the appropriate location:
   - Read `.observo-toolkit.json:prd_save_dir` if present — save under that directory.
   - Otherwise default to `./docs/PRDs/PRD-<feature-name>.md` (create the directory if missing).
   - If neither path is suitable for the repo, ask the user via `AskUserQuestion` for the target path before writing.

## PRD Structure

```
# PRD: <Feature Name>

**Author:** <from context, or ask the user>
**Date:** <today>
**Status:** Draft
**Source:** <where the requirements came from, e.g. "Meeting YYYY-MM-DD with X">

---

## Overview
One paragraph — what this is and why we need it.

## Problem Statement
What is broken or missing today.

## Goals
Numbered list of concrete outcomes.

## Non-Goals
What is explicitly out of scope for this iteration.

## User Stories
Table: # | As a… | I want to… | So that…

## Data Model
Field table: Field | Source | Notes
Source — one of: System / Pulled from <Entity> / Bot (from <origin>) / Manual (<who>)

## API Endpoints (if applicable)
Table: Method | Path | Description

## UI (if applicable)
Key screens and interactions. Call out which parts are read-only vs editable, and by whom.

## Integrations (if applicable)
External systems (bots, Slack, third-party services) and the contract they must adhere to.

## Acceptance Criteria
Checklist of verifiable conditions.

## Out of Scope (Future)
Explicitly deferred items.
```

## Notes on tone and decisions

- Always annotate each data field with its source (auto-pulled, bot-filled, manual).
- Capture who owns each manually-filled field by name if mentioned.
- When the transcript contains an explicit agreement ("we decided X"), record it as a decision, not a suggestion.
- Keep language direct and implementation-agnostic unless the transcript specifies a technology.
