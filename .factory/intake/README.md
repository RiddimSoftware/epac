# Intake Session Provenance

Optional local agent hooks write intake-session provenance under this directory.
The hook is capture-only: it records local context for bug, feature, fact-check,
and open-data intake modes without changing the implementation workflow.

## Session Files

Each session writes to `.factory/intake/sessions/<session-id>/`.

- `events.jsonl` stores the raw hook event stream with redacted prompt, tool
  input, and tool response summaries.
- `session.json` stores the durable session envelope:
  `session_id`, `started_at`, `mode`, `agent`, and, after `stop`, `ended_at`
  plus `duration_seconds`.
- `transcript.md` stores submitted user prompts as timestamped fenced blocks.
- `issues.jsonl` stores GitHub issue URLs created from captured
  `gh issue create` Bash calls.
- `summary.json` and `unfinished-intake.md` preserve the existing bugfix SPEC
  receipt and abandoned-intake behavior.

## Index Rollup

On `stop`, the hook appends one JSON Lines record to
`.factory/intake/index.jsonl` so external tools can enumerate intake sessions
without walking every session directory.

Schema:

```json
{
  "session_id": "sess-123",
  "started_at": "2026-05-22T20:00:00Z",
  "ended_at": "2026-05-22T20:05:00Z",
  "mode": "feature",
  "agent": "codex",
  "issue_urls": ["https://github.com/RiddimSoftware/epac/issues/123"],
  "duration_seconds": 300
}
```

`mode` comes from `EPAC_INTAKE_MODE` when set; otherwise it is
`unspecified`. `agent` comes from `EPAC_INTAKE_AGENT` when set, then falls back
to the captured tool source inference.
