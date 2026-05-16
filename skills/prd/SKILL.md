---
name: prd
description: Write a structured PRD from raw user input — meeting transcripts, notes, or feature descriptions. Body in Russian, section headings in English. Use when the user asks to "напиши PRD", "створи PRD", "draft a PRD", "write a PRD for <feature>", "PRD из транскрипта/нотаток", or provides meeting notes / requirements text expecting a structured product spec back. Default save location in this repo: `kb-observo/20 - Projects/<ProjectName>/PRD-<feature-name>.md`.
---

# PRD Skill — Write a PRD from user input

The user will provide raw input — typically a meeting transcript, notes, or a brief description of a feature. Your job is to produce a structured PRD.

**Language: Write PRD content in Russian, but keep all section headings in English.** Descriptions, field notes, user stories, and body text must be in Russian. Section headings (Overview, Goals, Data Model, etc.) and code identifiers (field names, endpoints) stay in English.

## Steps

1. Read everything the user provides. If it's a meeting transcript, extract decisions, requirements, field names, data sources, and explicit non-goals.
2. Ask no clarifying questions unless a critical piece is truly missing (e.g. no target product mentioned at all). Make reasonable assumptions and note them.
3. Write the PRD using the structure below: headings in English, body text in Russian.
4. Save the file to the appropriate location. In this repo (observo), default to `kb-observo/20 - Projects/<ProjectName>/PRD-<feature-name>.md` if such a folder structure exists; otherwise ask the user for the target path or save next to related docs.

## PRD Structure

```
# PRD: <Feature Name>

**Author:** <из контекста или Blake>
**Date:** <сегодня>
**Status:** Draft
**Source:** <откуда требования, например "Meeting YYYY-MM-DD with X">

---

## Overview
Один абзац — что это и зачем нужно.

## Problem Statement
Что сломано или отсутствует сейчас.

## Goals
Нумерованный список конкретных результатов.

## Non-Goals
Что явно не входит в эту итерацию.

## User Stories
Таблица: # | As a… | I want to… | So that…

## Data Model
Таблица полей: Field | Source | Notes
Source — одно из: System / Pulled from <Entity> / Bot (from <origin>) / Manual (<кто>)

## API Endpoints (if applicable)
Таблица: Method | Path | Description

## UI (if applicable)
Описание ключевых экранов и взаимодействий. Указать, что read-only, что редактируемо и кем.

## Integrations (if applicable)
Внешние системы (боты, Slack и т.д.) и контракт, которому они должны соответствовать.

## Acceptance Criteria
Чеклист проверяемых условий.

## Out of Scope (Future)
Список явно отложенных вещей.
```

## Notes on tone and decisions
- Always annotate each data field with its source (auto-pulled, bot-filled, manual).
- Capture who owns each manually-filled field by name if mentioned.
- When the transcript contains an explicit agreement ("we decided X"), record it as a decision, not a suggestion.
- Keep language direct and implementation-agnostic unless the transcript specifies a technology.
