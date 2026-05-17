# Telemetry

This document describes every telemetry signal recorded by the
`observo-qa-toolkit` plugin and the hosted Observo MCP server. It is the
single source of truth — no event field exists in production that is not
listed here.

## Layers

Telemetry has two independent layers:

| Layer | Where | Who controls it | What it captures |
|---|---|---|---|
| **Layer 1** | Hosted MCP server (`mcp.observoai.co`) | Observo | Every MCP tool call. Used to understand which tools are popular, error rates, and aggregate latency. |
| **Layer 2** | Plugin-side opt-in beacon | You (via `.observo-toolkit.json:telemetry_enabled`) | Skill-level events that are invisible at the MCP-tool layer (a skill that decided to skip, a `plugin_install` ping, etc.). |

Layer 1 is on whenever you use the hosted MCP. Layer 2 is **off by default**
and only fires when you opt in.

## Layer 1 — hosted MCP server

### What is recorded

Per MCP `tools/call` request, one row is written to a server-side
`mcp_telemetry_events` table with the following fields:

| Field | Type | Description |
|---|---|---|
| `account_id` | UUID | Your Observo account (already known to the server from your API key). Identifies *whose* aggregate usage this contributes to. |
| `event_type` | enum string | `tool_invoke` for normal tool calls; `unknown_tool_invoke` when the client named a tool that does not exist on this server (see [below](#unknown_tool_invoke-events)). |
| `tool_name` | string | The MCP tool name (e.g. `create_test_case`, `list_runs`). No `mcp__observo__` prefix. For `unknown_tool_invoke` events: whatever name the client *requested* (e.g. `archive_plan`). |
| `status` | enum string | `ok` on success, `error` on failure. `unknown_tool_invoke` rows are always `error`. |
| `error_code` | enum string \| `null` | Short opaque category: `bad_request` \| `not_found` \| `forbidden` \| `internal` \| `timeout` \| `unknown`. `null` when `status = ok`. Never an error message body. `unknown_tool_invoke` rows are always `not_found`. |
| `duration_ms` | int32 \| `null` | Wall-clock latency of the tool handler. Capped at int32 max. `null` for `unknown_tool_invoke` events (the handler never ran). |
| `plugin_version` | string \| `null` | Always `null` for Layer 1. Reserved for Layer 2. |
| `arg_schema` | JSON object \| `null` | OB-276: schema-only sampling of the tool's argument shape. See [arg_schema below](#arg_schema-field). `null` for `unknown_tool_invoke` events and when the middleware could not compute a schema. |
| `created_at` | timestamptz | Insert time, UTC. |

### What is NOT recorded

- Tool **input values** (test case names, descriptions, file paths, prompts). `arg_schema` records field *names* and *byte sizes* — never values. See the field section below.
- Tool output payloads (response bodies, generated artifacts).
- Error message text or stack traces.
- User identities beyond the account-scoped `account_id`.
- IP addresses, user-agents, or any HTTP request metadata other than the
  authorization header (which is decoded into `account_id` and discarded).
- Anything from the request body other than the JSON-RPC envelope's
  `method`, `params.name`, and the **top-level keys** of `params.arguments`
  (the body is rewound for the handler and never persisted; values inside
  arguments are kept as opaque bytes and only their lengths are recorded).

### `unknown_tool_invoke` events

When a client (Claude or otherwise) calls `tools/call` with a tool name the
server has never heard of, the MCP SDK rejects the request with its standard
`Method not found` response. Independently, the middleware records the
requested name as an `unknown_tool_invoke` row. This is product-demand data:
the client has already translated a human prompt into a concrete tool
identifier and we want to know which capabilities people reach for.

Privacy posture is identical to `tool_invoke`: only the **requested name** is
captured. There are no arguments, no payload, no `plugin_version`, and no
`duration_ms`. `unknown_tool_invoke` rows are visually distinct from real
handler errors because they always carry `status=error` + `error_code=not_found`
and `arg_schema=null`.

### `arg_schema` field

For each successful `tool_invoke` row, the middleware also records a
schema-only sampling of the tool's argument shape — **never the values
themselves**. Shape:

```json
{
  "present_fields": ["name", "severity", "description"],
  "field_sizes":    {"name": 5, "severity": 6, "description": 5}
}
```

- `present_fields` — top-level keys present in `params.arguments`, in
  document order. Nested keys are NOT recursed (they may be free-form
  user input; only top-level keys are part of the public MCP tool schema).
- `field_sizes` — JSON-encoded byte length of each top-level value
  (e.g. `"foo"` → 5, `null` → 4, `{"a":1}` → 7). Strings include their
  surrounding quotes.

The payload is capped at **4 KiB** end-to-end (the mcp/ middleware
short-circuits before emitting; the server independently rejects oversized
or non-object payloads). On overflow or malformed input the row is still
inserted with `arg_schema = null` — the cap never breaks the user's tool
call. Aggregate queries that care about argument schema should filter
`WHERE arg_schema IS NOT NULL`.

### Can I opt out of Layer 1?

Layer 1 is hosted-side telemetry; it is on for every account using
`mcp.observoai.co`. The fields recorded are aggregate-analytics only —
there is no PII and no payload data. If your compliance posture
requires no telemetry at all, contact us via the
[issues page](https://github.com/observo-ai/observo-qa-toolkit/issues)
and we will discuss alternatives.

## Layer 2 — plugin-side opt-in beacon

### How to enable

In your repo's `.observo-toolkit.json`:

```json
{ "telemetry_enabled": true }
```

The flag is **`false` by default**. With it false (or the file absent),
skills do not call the beacon and no Layer 2 events are recorded.

### What is recorded

When skills emit beacon calls (and only when), the same
`mcp_telemetry_events` table receives rows with these fields:

| Field | Type | Description |
|---|---|---|
| `account_id` | UUID | Your account. Same as Layer 1. |
| `event_type` | enum string | `skill_invoke` \| `skill_completed` \| `skill_skipped` \| `plugin_install`. |
| `tool_name` | string | The skill name (e.g. `prd`, `pw-generate`). For `plugin_install` events, the sentinel `plugin`. |
| `plugin_version` | string | Plugin semver from `.claude-plugin/plugin.json`, e.g. `1.1.1`. Resolved from the highest-versioned directory under `~/.claude/plugins/cache/<marketplace>/observo-qa-toolkit/` (the canonical install path), falling back to `~/.claude/plugins/observo-qa-toolkit/`, the consumer repo's submodule, then alt config locations. Cache-first ordering ensures `/plugin update` is reflected immediately; submodule pins (which lag upstream) are last. |
| `status` | enum string | Always `ok` for beacon events. Layer 2 is informational, not an error channel. |
| `error_code` | `null` | Always `null` for Layer 2. |
| `duration_ms` | `0` | Not meaningful for beacon events. |
| `created_at` | timestamptz | Insert time, UTC. |

### What is NOT recorded

- Same exclusions as Layer 1 — no payloads, no PII, no message bodies.
- Skill arguments, user prompts, generated content.
- Which specific Observo case / suite / project the skill was working on.

### Beacon source

Skills that emit beacons call the `mcp__observo__telemetry_event` MCP tool
with exactly three arguments:

```
mcp__observo__telemetry_event(
  event_type   = "skill_invoke" | "skill_completed" | "skill_skipped" | "plugin_install",
  plugin_version = "1.0.0",                                  // semver
  skill_name   = "prd" | "pw-generate" | ...                  // omitted for plugin_install
)
```

There is no other channel through which a Layer 2 row can be created.

## Retention

Telemetry rows are retained for **90 days** rolling. Beyond 90 days, rows
are aggregated into daily summaries (tool/skill counts and error rates by
account) and the raw rows are deleted. Aggregates have no per-row data
and cannot reconstruct an individual usage timeline.

## Access

Telemetry data is accessible only to Observo operators. It is not
exposed in the customer-facing UI or API. Per-customer aggregates may be
shared with the customer on request via the
[issues page](https://github.com/observo-ai/observo-qa-toolkit/issues).

## Changes to this document

Any change to the telemetry fields recorded — adding a field, adding an
event type, changing retention — is communicated by:

1. A bumped plugin version (semver minor for new fields, semver major if
   any field semantics change in a backwards-incompatible way).
2. A `CHANGELOG.md` entry calling out the telemetry change explicitly.
3. An updated version of this document committed in the same release.

If you find a discrepancy between what is documented here and what is
actually recorded, that is a bug — please file an issue.
