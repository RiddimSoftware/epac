# Optional Bugfix Intake Session Hooks

The bugfix intake harness works from a fresh clone without hooks:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

For the demo path that should open with bug-report intake, start Claude with
the trigger prompt:

```bash
claude bugfix
```

Hooks are an optional trusted capture layer for local LLM sessions. They record
coarse intake-session provenance so an abandoned bugfix conversation still
leaves a follow-up signal.

## Trust Boundary

Do not enable hooks unless you trust the local repository checkout and understand
the tool permissions being granted. Hook payloads may include prompt text, tool
names, tool input, tool responses, cwd, and transcript paths. The hook redacts
obvious password, token, secret, authorization, and long bearer-like values, but
it is still a local logging mechanism.

The example config is deliberately not auto-enabled:

```text
.factory/hooks/claude-settings.example.json
```

Copy the relevant entries into your own Claude Code settings only when you want
trusted session capture for this checkout.

## Captured Files

Hook events are appended as JSON Lines:

```text
.factory/intake/sessions/<session-id>/events.jsonl
```

The hook supports these subcommands:

- `session-start`
- `user-prompt-submit`
- `post-tool-use`
- `stop`

`session-start` records the session only. It does not emit bug-report context,
because Claude Code treats `SessionStart` stdout as hidden context for the
first model request. The `user-prompt-submit` hook enters bug-report intake only
when the first prompt is exactly `bugfix` or `/bugfix`. A plain `claude`
session, or a session started with any other prompt, remains normal development
mode. Set `EPAC_BUG_INTAKE_SESSION_START=0` to keep capture hooks enabled while
suppressing the bug-report trigger.

On `stop`, the hook writes:

```text
.factory/intake/sessions/<session-id>/summary.json
```

If the session produced a valid bugfix SPEC receipt, the summary records
`terminalState=spec_valid`. If no valid receipt is found, the hook writes
`terminalState=unfinished_intake` and also creates:

```text
.factory/intake/sessions/<session-id>/unfinished-intake.md
```

Stop hooks are capture-only. They do not block session shutdown.

## SPEC Receipts

`bugfix_spec.py new` writes a `receipt.json` next to every valid `SPEC.md`.
The receipt includes the trace ID, target repo, SPEC path, reporter, source,
affected surface, source tool when supplied, session ID when supplied, and
`terminalState=spec_valid`.

Pass provenance explicitly:

```bash
python3 scripts/intake/bugfix_spec.py new \
  --source-tool claude \
  --session-id "$BUGFIX_SESSION_ID"
```

Or provide it through the environment:

```bash
BUGFIX_SOURCE_TOOL=claude BUGFIX_SESSION_ID=sess-123 python3 scripts/intake/bugfix_spec.py new
```
