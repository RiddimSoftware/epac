#!/usr/bin/env bash
# Smoke test for codex intake hooks.
# Invokes the hook handler directly with synthetic payloads — no live codex session needed.
# Validates that each hook event creates the expected files in .factory/intake/sessions/<id>/.
#
# Usage: bash scripts/intake/test_codex_hooks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
SESSION_ID="test-codex-hooks-$(date +%s)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

HOOK="$REPO_ROOT/scripts/intake/intake_session_hook.py"
HOOK_NAME="intake_session_hook.py"
[ -f "$HOOK" ] || { echo "FAIL  intake_session_hook.py is missing"; exit 1; }

echo "handler: $HOOK_NAME"
echo "session: $SESSION_ID"
echo "work dir: $WORK_DIR"
echo ""

SESSIONS_DIR="$WORK_DIR/.factory/intake/sessions"
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; exit 1; }

# --- session-start ---
echo '--- session-start ---'
printf '{"session_id":"%s","hook_event_name":"SessionStart","cwd":"%s","model":"gpt-5.3-codex-spark","transcript_path":null}' \
    "$SESSION_ID" "$REPO_ROOT" \
    | EPAC_INTAKE_ROOT="$WORK_DIR" EPAC_INTAKE_MODE="bug" EPAC_INTAKE_AGENT="codex" python3 "$HOOK" session-start
[ -f "$SESSION_DIR/events.jsonl" ] || fail "events.jsonl not created after session-start"
[ -f "$SESSION_DIR/session.json" ] || fail "session.json not created after session-start"
python3 -c "
import json, sys
lines = open('$SESSION_DIR/events.jsonl').read().splitlines()
events = [json.loads(l) for l in lines if l.strip()]
assert any(e.get('hookEvent') == 'session-start' for e in events), 'session-start event missing'
session = json.load(open('$SESSION_DIR/session.json'))
assert session.get('mode') == 'bug', 'mode not captured'
assert session.get('agent') == 'codex', 'agent not captured'
" || fail "session-start event not in events.jsonl"
pass "session-start writes session metadata"

# --- user-prompt-submit ---
echo '--- user-prompt-submit ---'
printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","cwd":"%s","model":"gpt-5.3-codex-spark","transcript_path":null,"prompt":"file a bug report about crash on launch"}' \
    "$SESSION_ID" "$REPO_ROOT" \
    | EPAC_INTAKE_ROOT="$WORK_DIR" python3 "$HOOK" user-prompt-submit
[ -f "$SESSION_DIR/transcript.md" ] || fail "transcript.md not created after user-prompt-submit"
python3 -c "
import json
lines = open('$SESSION_DIR/events.jsonl').read().splitlines()
events = [json.loads(l) for l in lines if l.strip()]
assert any(e.get('hookEvent') == 'user-prompt-submit' for e in events), 'user-prompt-submit event missing'
transcript = open('$SESSION_DIR/transcript.md').read()
assert 'file a bug report about crash on launch' in transcript, 'prompt missing from transcript.md'
" || fail "user-prompt-submit event not in events.jsonl"
pass "user-prompt-submit appends to transcript.md"

# --- post-tool-use (Bash with gh issue create) ---
echo '--- post-tool-use ---'
printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","model":"gpt-5.3-codex-spark","transcript_path":null,"tool_name":"Bash","tool_use_id":"call_test123","tool_input":{"command":"gh issue create --title '\''Crash on launch'\'' --body '\''app crashes'\''"},"tool_response":{"content":[{"type":"text","text":"https://github.com/RiddimSoftware/epac/issues/42"}]}}' \
    "$SESSION_ID" "$REPO_ROOT" \
    | EPAC_INTAKE_ROOT="$WORK_DIR" python3 "$HOOK" post-tool-use
[ -f "$SESSION_DIR/issues.jsonl" ] || fail "issues.jsonl not created after gh issue create"
python3 -c "
import json
lines = open('$SESSION_DIR/events.jsonl').read().splitlines()
events = [json.loads(l) for l in lines if l.strip()]
assert any(e.get('hookEvent') == 'post-tool-use' for e in events), 'post-tool-use event missing'
issues = [json.loads(l) for l in open('$SESSION_DIR/issues.jsonl').read().splitlines() if l.strip()]
assert issues and issues[0].get('issue_url') == 'https://github.com/RiddimSoftware/epac/issues/42', 'issue URL missing'
" || fail "post-tool-use event not in events.jsonl"
pass "post-tool-use records issue URL"

# --- stop ---
echo '--- stop ---'
printf '{"session_id":"%s","hook_event_name":"Stop","cwd":"%s","model":"gpt-5.3-codex-spark","transcript_path":null,"stop_hook_active":false,"last_assistant_message":"intake complete"}' \
    "$SESSION_ID" "$REPO_ROOT" \
    | EPAC_INTAKE_ROOT="$WORK_DIR" python3 "$HOOK" stop
[ -f "$SESSION_DIR/summary.json" ] || fail "summary.json not created after stop"
[ -f "$WORK_DIR/.factory/intake/index.jsonl" ] || fail "index.jsonl not created after stop"
python3 -c "
import json
d = json.load(open('$SESSION_DIR/summary.json'))
assert d.get('kind') in ('bugfix_session_summary', 'intake_session_summary'), 'wrong kind: ' + str(d.get('kind'))
assert d.get('eventCount', 0) >= 4, 'expected >= 4 events, got ' + str(d.get('eventCount'))
session = json.load(open('$SESSION_DIR/session.json'))
assert 'ended_at' in session, 'ended_at missing from session.json'
index = [json.loads(l) for l in open('$WORK_DIR/.factory/intake/index.jsonl').read().splitlines() if l.strip()]
assert index and index[-1].get('issue_urls') == ['https://github.com/RiddimSoftware/epac/issues/42'], 'index issue URLs missing'
" || fail "summary.json missing expected fields"
EVENT_COUNT="$(python3 -c "import json; print(json.load(open('$SESSION_DIR/summary.json'))['eventCount'])")"
pass "stop writes summary.json with $EVENT_COUNT events"

echo ""
echo "All smoke tests passed."
echo "events.jsonl: $(wc -l < "$SESSION_DIR/events.jsonl") lines"
echo "summary.json: $(python3 -c "import json; d=json.load(open('$SESSION_DIR/summary.json')); print(d['terminalState'])")"
