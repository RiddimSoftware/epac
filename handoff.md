## Implementation notes

Added codex-side intake provenance hooks to mirror the Claude Code hook structure in `.claude/settings.json`.

Three new files:
- `.codex/config.toml`: TOML hook config read automatically by codex when the session cwd is inside the repo. Registers all four lifecycle events (SessionStart, UserPromptSubmit, PostToolUse with matcher `*`, Stop), each invoking `scripts/intake/intake_session_hook.py <subcommand>`. The handler rename (EPAC-1950) is a dependency — config references the post-rename name but the smoke test falls back to `bugfix_session_hook.py` while pending.
- `.codex/README.md`: investigation notes documenting hook discovery order (4 locations merged), supported events, payload schema (JSON on stdin), and a diff table vs Claude Code.
- `scripts/intake/test_codex_hooks.sh`: smoke test that drives the handler with synthetic payloads for all four events. Validates `events.jsonl` and `summary.json` without a live codex session.

`.gitignore` was updated to replace the blanket `.codex/` ignore with `.codex/sessions/` and `.codex/cache/` so the config and README are tracked.

The WIP commit from the previous attempt included a `.claude/settings.json` reformat (same content, different whitespace) — that stays in the branch as it's already committed.

## Verification evidence

```
bash scripts/intake/test_codex_hooks.sh

handler: bugfix_session_hook.py (rename to intake_session_hook.py pending EPAC-1950)
session: test-codex-hooks-1779484506

--- session-start ---
PASS  session-start writes to events.jsonl
--- user-prompt-submit ---
PASS  user-prompt-submit appends to events.jsonl
--- post-tool-use ---
PASS  post-tool-use appends to events.jsonl
--- stop ---
PASS  stop writes summary.json with 4 events

All smoke tests passed.
events.jsonl: 4 lines
summary.json: unfinished_intake
```

PR: https://github.com/RiddimSoftware/epac/pull/521

## Tradeoffs

- TOML format over JSON (`hooks.json`) per issue title; avoids duplicate-source warning if a future contributor adds `.codex/hooks.json`.
- PostToolUse matcher `*` (all tools) to match the Claude Code hook's `*` matcher. The handler already filters internally.
- Smoke test invokes handler directly (not a live codex session) for speed and CI suitability.

## Blockers / follow-ups

- EPAC-1950 (rename `bugfix_session_hook.py` → `intake_session_hook.py`) must land before codex sessions invoke the correct handler path. Config is already forward-compatible.
- Acceptance criteria mention `session.json`, `transcript.md`, and `issues.jsonl` as output files; the current handler writes `events.jsonl` and `summary.json`. Those specific output files are a handler concern (out of scope per issue spec — "Modifying the intake_session_hook.py handler itself is a separate issue").
