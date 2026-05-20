#!/usr/bin/env bash
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"

read -r -d '' PROMPT <<'PROMPT' || true
Start epac bug report intake.

Bug report mode is the default for this session. Ask me to choose:

1. File a bug report
2. Exit bug-report mode and use normal development mode

If I choose 1 or describe a bug, collect only missing fields:
- title
- reporter GitHub username or email, if I want follow-up
- affected screen or feature
- observed behavior
- expected behavior
- reproduction steps
- evidence that would prove the fix
- reporter/TestFlight validation plan

Do not implement code during intake. When enough detail exists, run:

python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md

Then report the SPEC.md path, trace ID, summary, evidence plan, and whether it is ready to become a GitHub Issue.
PROMPT

exec "$CLAUDE_BIN" --name epac-bug-report "$PROMPT"
