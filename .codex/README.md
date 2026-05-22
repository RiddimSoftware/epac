# Codex Hook Configuration

This directory holds the repo-local codex hook configuration for epac intake provenance.

## Investigation findings (EPAC-1951)

**Codex version verified:** 0.130.0  
**Reference:** `software-factory/docs/spikes/codex-provenance-hooks.md` (FAC-43)

### Where codex looks for hook configuration

Codex merges hooks from four locations (all loaded, not overriding):

| Precedence | Location | Notes |
|---|---|---|
| 1 | `~/.codex/hooks.json` | Global JSON hooks |
| 2 | `~/.codex/config.toml` | Global TOML inline `[[hooks.*]]` tables |
| 3 | `<repo>/.codex/hooks.json` | Repo-local JSON hooks |
| 4 | `<repo>/.codex/config.toml` | Repo-local TOML hooks ← **this file** |

Repo-local discovery triggers when the codex session's cwd is inside the repo. The feature toggle is `[features] hooks = true` in `~/.codex/config.toml`; it is on by default since 0.130.0.

### Supported hook events

| Event | Matcher | Fires when |
|---|---|---|
| `SessionStart` | `source` field (`startup`, `resume`, `clear`) | Session starts |
| `UserPromptSubmit` | Ignored | Before user prompt is sent to model |
| `PreToolUse` | `tool_name` | Before a tool call |
| `PermissionRequest` | `tool_name` | Before an approval prompt |
| `PostToolUse` | `tool_name` | After a tool call completes |
| `Stop` | Ignored | Session stop / turn end |

All four events used by the intake harness (`SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Stop`) are natively supported.

### Config format

**TOML inline format** (used in `config.toml`):

```toml
[[hooks.PostToolUse]]
matcher = "Bash"

[[hooks.PostToolUse.hooks]]
type = "command"
command = "python3 scripts/intake/intake_session_hook.py post-tool-use"
timeout = 30
```

**JSON format** (alternative, used in `hooks.json`):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 scripts/intake/intake_session_hook.py post-tool-use",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Do not create both `config.toml` and `hooks.json` in `.codex/` — codex merges both and warns on duplicate events.

### Payload transport

All hook events deliver a JSON object on **stdin** (not environment variables or argv). The handler reads `sys.stdin` and parses it.

Key fields present on every event:

| Field | Type | Notes |
|---|---|---|
| `session_id` | `string` | UUID v7 — use this as the canonical session key |
| `hook_event_name` | `string` | `"SessionStart"`, `"PostToolUse"`, etc. |
| `transcript_path` | `string \| null` | Absolute path to the `.jsonl` transcript |
| `cwd` | `string` | Session working directory |
| `model` | `string` | Active model slug |

`PostToolUse` adds: `tool_name`, `tool_use_id`, `tool_input`, `tool_response`.  
`Stop` adds: `stop_hook_active`, `last_assistant_message`.

### Behavioural differences from Claude Code (`.claude/settings.json`)

| Aspect | Claude Code | Codex |
|---|---|---|
| Config file | `.claude/settings.json` (JSON) | `.codex/config.toml` (TOML) or `.codex/hooks.json` |
| Session ID format | `claude-code-<timestamp>-<random>` | UUID v7 |
| Transcript path in payload | Not surfaced | Present on every event |
| Stop matcher | N/A | Ignored — fires on every stop |
| UserPromptSubmit matcher | Supported | Ignored |
| Default hook timeout | ~4 s | **600 s** — always set an explicit `timeout` |
| Trust model | `/hooks` browser | SHA-256 hash stored in `~/.codex/config.toml` `[hooks.state]` |

### Gaps

None for this use case. All four required events (`SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Stop`) are supported by codex 0.130.0.

## Handler dependency

The hooks in `config.toml` invoke `scripts/intake/intake_session_hook.py`.  
This file is created by EPAC-1950 (rename from `bugfix_session_hook.py`).  
Until that issue merges, the smoke test falls back to `bugfix_session_hook.py`, which exposes the same subcommand interface.

## Smoke test

```bash
bash scripts/intake/test_codex_hooks.sh
```

Invokes the handler directly with synthetic payloads — no live codex session required. Validates that each hook event creates the expected files under `.factory/intake/sessions/<id>/`.
