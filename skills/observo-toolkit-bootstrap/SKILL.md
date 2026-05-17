---
name: observo-toolkit-bootstrap
description: Record one plugin_install telemetry event per consumer repo, idempotently. Reads `.observo-toolkit.json:telemetry_enabled` as the opt-in gate (default false) and `.claude-plugin/plugin.json:version` for the version field. Writes a marker file `.observo-toolkit/.install-seeded` so subsequent invocations are a no-op until the plugin version changes. Use when the user asks to "set up observo-qa-toolkit", "initialize observo plugin telemetry", "bootstrap observo toolkit", or as a one-time first-run step after enabling telemetry. The skill is privacy-first — when the opt-in flag is false or absent, the skill exits silently and records nothing.
---

# observo-toolkit-bootstrap

Send the `plugin_install` Layer 2 telemetry beacon **exactly once per consumer
repo**, gated on the user's opt-in. After the first successful run, subsequent
invocations are a no-op until the plugin version changes (upgrade re-seed).

The beacon is what gives the Observo team a discrete "install" data point —
without it, Layer 1 server-side telemetry only sees `tool_invoke` events and
cannot tell first-time installs from repeat usage.

## When to use

- The user just installed `observo-qa-toolkit` and is enabling telemetry for
  the first time (`.observo-toolkit.json:telemetry_enabled` flipped to `true`).
- The user explicitly asks to "set up observo-qa-toolkit", "bootstrap observo
  plugin", "initialize observo telemetry".
- The plugin version has changed in `.claude-plugin/plugin.json` since the
  last bootstrap (the skill detects this from the marker file and re-fires).

## When NOT to use

- The user has not opted in (`.observo-toolkit.json` missing, or
  `telemetry_enabled` is `false` / absent). The skill exits silently — opt-in
  means opt-in.
- Inside automated tests or CI runs where telemetry would pollute analytics.
- As an implicit step inside other skills — for v1 this skill is **explicit
  only**. Other skills do not auto-invoke it. (Auto-invocation may land as a
  follow-up if install-rate data turns out to be weak.)

## Inputs

None — the skill discovers everything it needs from the consumer repo and the
installed plugin.

## Workflow

### Step 1 — Read the opt-in flag

Read `.observo-toolkit.json` from the consumer repo root using the `Read` tool.

- If the file does not exist → exit with a single line:
  `Telemetry not configured (.observo-toolkit.json absent). Skipping bootstrap.`
- If the file exists but is malformed JSONC → exit with:
  `Could not parse .observo-toolkit.json. Skipping bootstrap.`
- Strip `//` comments, parse JSON, look for `telemetry_enabled`.
- If `telemetry_enabled` is anything other than literal boolean `true` → exit
  with: `Telemetry opt-in is off (telemetry_enabled = <value>). Nothing to do.`

**Do not** prompt the user to opt in. Opt-in is a deliberate config change the
user makes themselves; an interactive nudge would feel like dark-pattern
opt-in.

### Step 2 — Resolve the plugin version

The skill needs the plugin's own semver. Resolution order — **stop at the
first path that yields a parseable `version`**:

1. **Marketplace cache (canonical path for `/plugin install`).** Claude Code
   unpacks marketplace plugins into a versioned cache directory:

   ```
   $HOME/.claude/plugins/cache/<marketplace-name>/observo-qa-toolkit/<version>/.claude-plugin/plugin.json
   ```

   Multiple versions can coexist if `/plugin install` was run several times.
   Pick the **highest version directory** (the dir name itself is the semver
   — sort and take the last). Recommended one-liner:

   ```bash
   ls -1d $HOME/.claude/plugins/cache/*/observo-qa-toolkit/*/ 2>/dev/null \
     | sort -V | tail -n1
   ```

   Then read `.version` from `<dir>/.claude-plugin/plugin.json`. If `sort -V`
   is unavailable, fall back to plain `sort` (semver naming is mostly
   lex-equivalent for single-digit majors).

2. **Direct install:**
   `$HOME/.claude/plugins/observo-qa-toolkit/.claude-plugin/plugin.json`

3. **Submodule / vendored copy in the consumer repo** — useful only when the
   consumer is the Observo monorepo itself, which pins via git submodule:
   `./.claude/plugins/observo-qa-toolkit/.claude-plugin/plugin.json`

   ⚠️ This path is often **stale** (submodule pointer lags upstream `/plugin
   install` updates). It is intentionally last so the user's actual runtime
   version is preferred when both exist.

4. **Alternate config location:**
   `$HOME/.config/claude/plugins/observo-qa-toolkit/.claude-plugin/plugin.json`

Parse the JSON, read `.version` (e.g. `"1.1.1"`).

If no path yields a parseable `version` → exit with:
`Could not resolve plugin.json:version from any known install path. Bootstrap aborted (no beacon sent).`

Better to silently skip the beacon than to send a wrong / placeholder version.

**Why cache-first, not submodule-first**: when the user runs `/plugin update
observo-qa-toolkit`, only the cache path changes. The vendored / submodule
copy stays at whatever the consumer repo pinned. Sending the submodule
version as `plugin_version` would mis-attribute install events to a stale
release.

### Step 3 — Check the marker file

Marker path: `./.observo-toolkit/.install-seeded` (in the consumer repo, hidden
inside the `.observo-toolkit/` directory).

Expected content if exists (JSON):

```json
{
  "seeded_at": "2026-05-17T17:00:00Z",
  "plugin_version": "1.0.0"
}
```

Three decision branches:

1. **Marker absent** → first install on this repo → proceed to Step 4 (fresh
   seed).
2. **Marker present, `plugin_version` matches** → already seeded for this
   version → exit with:
   `Already bootstrapped for plugin version <version> on <seeded_at>. No-op.`
3. **Marker present, `plugin_version` differs** → upgrade re-seed → proceed
   to Step 4 with note that this is an upgrade.
4. **Marker present but malformed** → treat as absent (fall through to Step 4
   and overwrite).

### Step 4 — Emit the beacon

Call the MCP tool:

```
mcp__observo__telemetry_event(
  event_type     = "plugin_install",
  plugin_version = "<version from Step 2>"
  // skill_name omitted — required-empty for plugin_install
)
```

Expected response: `{"recorded": true}`.

On any error from the MCP call (network, 4xx, 5xx) — surface the error to the
user but **do not** abort the rest of the workflow (Step 5 still runs to
prevent retry-storms on subsequent invocations).

### Step 5 — Write or update the marker

Using `Write`, create / overwrite `./.observo-toolkit/.install-seeded` with:

```json
{
  "seeded_at": "<current UTC time, RFC3339>",
  "plugin_version": "<version from Step 2>"
}
```

Also ensure `./.observo-toolkit/.gitignore` exists with content:

```
*
!.gitignore
```

This nested `.gitignore` causes git to ignore everything inside
`.observo-toolkit/` (including the marker) **except** the `.gitignore` file
itself — so the directory's intent to be local-only is committable, but the
marker is never tracked. The user does not need to touch their root
`.gitignore`.

### Step 6 — One-line summary

Report exactly one short line:

- Fresh seed: `✓ Bootstrapped observo-qa-toolkit v<version>. Telemetry enabled for this repo.`
- Upgrade re-seed: `✓ Re-bootstrapped from v<old> to v<new>. plugin_install event sent.`
- No-op: `Already bootstrapped for v<version> on <date>. No-op.`
- Opt-out: `Telemetry opt-in is off. Nothing to do.`
- Aborted: `Could not resolve plugin version. Bootstrap aborted (no beacon sent).`

No further prose — the user invoked an idempotent bootstrap, not a tutorial.

## Marker file format

`.observo-toolkit/.install-seeded` is a small JSON document, never edited by
the user manually. Fields:

| Field | Type | Purpose |
|---|---|---|
| `seeded_at` | RFC3339 timestamp (UTC) | When the most recent bootstrap completed. |
| `plugin_version` | semver string | Plugin version at the time of seed. |

To force a re-seed (e.g. for testing), delete the marker file and re-invoke
the skill.

## Anti-patterns

- ❌ **Sending the beacon without checking the opt-in flag.** This is the one
  hard rule. The beacon must never fire when `telemetry_enabled` is not
  `true`. Privacy-by-default is the contract documented in TELEMETRY.md.
- ❌ **Falling back to a placeholder plugin version** (e.g. `"unknown"`,
  `"0.0.0"`). Aggregate-version analytics on the server side would be
  poisoned. Skip the beacon if the version can't be resolved.
- ❌ **Prompting the user to opt in.** The flag is a deliberate, written
  config change. An interactive prompt converts an explicit opt-in into a
  pressured choice.
- ❌ **Writing the marker before the beacon attempt.** If the marker is
  written first and the beacon then fails, retries are impossible without
  manual marker deletion. Order: beacon → marker.
- ❌ **Retrying the beacon in a loop.** A single best-effort call is enough.
  Network blips are absorbed by the user's next bootstrap attempt; the marker
  ensures we don't pile up duplicate `plugin_install` events.
- ❌ **Reading any payload from `.observo-toolkit.json` other than
  `telemetry_enabled`.** Other fields (project codes, assignees, paths) are
  none of this skill's business. Stay narrow.
- ❌ **Writing extra fields into the marker.** No paths, no user identities,
  no system info. Only `seeded_at` and `plugin_version`. The marker is local
  and small on purpose.
- ❌ **Auto-invoking this skill from inside other skills.** v1 contract is
  explicit-only. If you want a different policy, change the policy in the
  PRD first.

## MCP tools used

- `mcp__observo__telemetry_event` — once per fresh seed or upgrade.

Read-only otherwise. No suite / project / case mutations.

## Privacy invariants

- The skill records exactly two pieces of data on the Observo side:
  `account_id` (already known from the user's API key) and `plugin_version`.
  Nothing else.
- The marker file lives only in the consumer repo's working tree (local), is
  never committed by default (nested `.gitignore`), and contains no
  user-identifying information.
- See [TELEMETRY.md](../../TELEMETRY.md) in the plugin repo root for the full
  event-field disclosure that this skill participates in.
