#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$ROOT_DIR/.factory/skills/intake-router.md"
BODY_CONTRACT="$ROOT_DIR/.factory/prompts/intake-issue-body.md"

fail() {
  echo "router skill test failed: $*" >&2
  exit 1
}

[[ -f "$SKILL_FILE" ]] || fail "missing .factory/skills/intake-router.md"
[[ -f "$BODY_CONTRACT" ]] || fail "missing referenced body contract: .factory/prompts/intake-issue-body.md"

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

def route_for(attendee_input: str) -> str:
    value = attendee_input.lower()
    if value == "1" or any(cue in value for cue in ["bug", "wrong", "crashes", "doesn't work"]):
        return ".factory/prompts/bug-report.md"
    if value == "2" or any(cue in value for cue in ["feature", "could it", "i wish", "add support for"]):
        return ".factory/prompts/feature-spec.md"
    if value == "3" or any(cue in value for cue in ["why", "where does this data come from", "what's in the code"]):
        return ".factory/prompts/audit.md"
    if value == "4" or any(cue in value for cue in ["open data", "csv", "api", "dataset", "government data"]):
        return ".factory/prompts/open-data-feature.md"
    raise AssertionError(f"unroutable canned attendee input: {attendee_input}")


canned_routes = [
    ("1", ".factory/prompts/bug-report.md"),
    ("I noticed the calendar shows the wrong month", ".factory/prompts/bug-report.md"),
    ("2", ".factory/prompts/feature-spec.md"),
    ("Could it let me follow a bill?", ".factory/prompts/feature-spec.md"),
    ("3", ".factory/prompts/audit.md"),
    ("Where does this data come from?", ".factory/prompts/audit.md"),
    ("4", ".factory/prompts/open-data-feature.md"),
    ("I have a government CSV source", ".factory/prompts/open-data-feature.md"),
]

for attendee_input, expected_protocol in canned_routes:
    actual_protocol = route_for(attendee_input)
    if actual_protocol != expected_protocol:
        raise SystemExit(
            f"canned attendee input routed to {actual_protocol}, "
            f"expected {expected_protocol}: {attendee_input}"
        )
    if expected_protocol not in text:
        raise SystemExit(f"router skill missing expected protocol: {expected_protocol}")

body_contract = (root / ".factory/prompts/intake-issue-body.md").read_text()
for required in [
    "Intake-Session:",
    "Reporter-Email:",
    "Mode: bug | feature | fact-check | open-data",
    "gh issue create",
]:
    if required not in body_contract:
        raise SystemExit(f"body contract missing required marker: {required}")
PY

echo "router skill test passed for canned attendee inputs"
