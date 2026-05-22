#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$ROOT_DIR/.factory/skills/intake-router.md"

fail() {
  echo "router skill test failed: $*" >&2
  exit 1
}

[[ -f "$SKILL_FILE" ]] || fail "missing .factory/skills/intake-router.md"

line_count="$(wc -l < "$SKILL_FILE" | tr -d ' ')"
[[ "$line_count" -le 200 ]] || fail "router skill has $line_count lines; expected <= 200"

python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
skill = root / ".factory/skills/intake-router.md"
text = skill.read_text()

greeting = """Hi! I'm Sunny's intake assistant for epac. I can help you with one of:
1. **Report a bug** — file it into the factory; you'll get a TestFlight invite when it ships.
2. **Suggest a feature** — same flow, different shape.
3. **Fact-check the app** — where does this data come from? What's in the code?
4. **Open-data feature** — you've got a government open-data source? I'll add it to epac.

What brings you here? (You can also just describe what you noticed and I'll figure out which it is.)"""

checks = {
    "exact greeting": greeting in text,
    "bug numeric route": '"1"' in text and ".factory/prompts/bug-report.md" in text,
    "bug language route": "calendar shows the wrong month" in text and ".factory/prompts/bug-report.md" in text,
    "feature numeric route": '"2"' in text and ".factory/prompts/feature-spec.md" in text,
    "fact check numeric route": '"3"' in text and ".factory/prompts/audit.md" in text,
    "fact check email optional": "email is optional" in text.lower(),
    "open data numeric route": '"4"' in text and ".factory/prompts/open-data-feature.md" in text,
    "body contract reference": ".factory/prompts/intake-issue-body.md" in text,
    "submission command": "gh issue create" in text,
    "live URL": "https://riddimsoftwarefactory.com/live" in text,
    "mode switching": "mode switch" in text.lower() or "switch modes" in text.lower(),
}

missing = [name for name, ok in checks.items() if not ok]
if missing:
    raise SystemExit("missing router content: " + ", ".join(missing))

for relative in [
    ".factory/prompts/bug-report.md",
    ".factory/prompts/feature-spec.md",
    ".factory/prompts/audit.md",
    ".factory/prompts/open-data-feature.md",
]:
    if not (root / relative).is_file():
        raise SystemExit(f"missing referenced placeholder protocol: {relative}")
PY

echo "router skill test passed"
