#!/usr/bin/env python3
"""Capture optional trusted bugfix-intake hook events."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4


ROOT = Path(os.environ.get("BUGFIX_INTAKE_ROOT", Path(__file__).resolve().parents[2]))
INTAKE_DIR = ROOT / ".factory" / "intake"
SESSIONS_DIR = INTAKE_DIR / "sessions"
MAX_SUMMARY_CHARS = 600

SECRET_KEY_RE = re.compile(r"(password|passwd|pwd|token|secret|api[_-]?key|authorization|auth)", re.IGNORECASE)
ASSIGNMENT_SECRET_RE = re.compile(
    r"\b(password|passwd|pwd|token|secret|api[_-]?key|authorization)\s*[:=]\s*[^,\s;&]+",
    re.IGNORECASE,
)
BEARER_RE = re.compile(r"Bearer\s+[A-Za-z0-9._~+/=-]{16,}", re.IGNORECASE)
LONG_TOKEN_RE = re.compile(r"\b(?=[A-Za-z0-9._~+/=-]*[A-Za-z])(?=[A-Za-z0-9._~+/=-]*\d)[A-Za-z0-9._~+/=-]{32,}\b")


def utc_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def redact_string(value: str) -> str:
    value = ASSIGNMENT_SECRET_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", value)
    value = BEARER_RE.sub("Bearer [REDACTED]", value)
    return LONG_TOKEN_RE.sub("[REDACTED]", value)


def redact(value: object, key: str = "") -> object:
    if SECRET_KEY_RE.search(key):
        return "[REDACTED]"
    if isinstance(value, dict):
        return {str(child_key): redact(child_value, str(child_key)) for child_key, child_value in value.items()}
    if isinstance(value, list):
        return [redact(item, key) for item in value]
    if isinstance(value, str):
        return redact_string(value)
    return value


def compact_summary(value: object) -> str:
    safe = redact(value)
    if isinstance(safe, str):
        text = safe
    else:
        text = json.dumps(safe, sort_keys=True, separators=(",", ":"))
    return text[:MAX_SUMMARY_CHARS]


def load_payload() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}
    return payload if isinstance(payload, dict) else {"payload": payload}


def first_string(payload: dict, *keys: str) -> str:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def session_id_for(payload: dict) -> str:
    return first_string(payload, "session_id", "sessionId", "sessionID") or os.environ.get("BUGFIX_SESSION_ID", "").strip() or f"manual-{uuid4().hex[:12]}"


def infer_source_tool(payload: dict) -> str:
    explicit = first_string(payload, "sourceTool", "source_tool", "tool")
    if explicit:
        return explicit
    env_value = os.environ.get("BUGFIX_SOURCE_TOOL", "").strip()
    if env_value:
        return env_value
    transcript = first_string(payload, "transcript_path", "transcriptPath", "transcript")
    if "codex" in transcript.lower():
        return "codex"
    if "claude" in transcript.lower() or transcript:
        return "claude"
    return "manual"


def transcript_path_for(payload: dict) -> str:
    return first_string(payload, "transcript_path", "transcriptPath", "transcript", "transcript_file")


def receipt_from_payload(payload: dict) -> dict | None:
    for key in ("receipt", "specReceipt", "bugfixReceipt"):
        value = payload.get(key)
        if isinstance(value, dict):
            return redact(value)  # type: ignore[return-value]
    for key in ("receiptPath", "receipt_path"):
        value = payload.get(key)
        if isinstance(value, str):
            path = Path(value)
            if path.exists():
                try:
                    data = json.loads(path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    return None
                return redact(data) if isinstance(data, dict) else None  # type: ignore[return-value]
    return None


def build_event(hook_event: str, payload: dict) -> dict:
    event = {
        "schemaVersion": 1,
        "timestamp": utc_now(),
        "hookEvent": hook_event,
        "session_id": session_id_for(payload),
        "sourceTool": infer_source_tool(payload),
    }
    cwd = first_string(payload, "cwd", "currentWorkingDirectory", "workspace")
    if cwd:
        event["cwd"] = cwd
    transcript_path = transcript_path_for(payload)
    if transcript_path:
        event["transcript_path"] = transcript_path
    prompt = first_string(payload, "prompt", "user_prompt", "userPrompt")
    if prompt:
        event["promptSummary"] = compact_summary(prompt)
    tool_name = first_string(payload, "tool_name", "toolName", "name")
    if tool_name:
        event["toolName"] = tool_name
    if "tool_input" in payload or "toolInput" in payload:
        event["toolInputSummary"] = compact_summary(payload.get("tool_input", payload.get("toolInput")))
    if "tool_response" in payload or "toolResponse" in payload:
        event["toolResponseSummary"] = compact_summary(payload.get("tool_response", payload.get("toolResponse")))
    receipt = receipt_from_payload(payload)
    if receipt:
        event["receipt"] = receipt
    return event


def session_dir(session_id: str) -> Path:
    return SESSIONS_DIR / session_id


def append_event(event: dict) -> Path:
    directory = session_dir(str(event["session_id"]))
    directory.mkdir(parents=True, exist_ok=True)
    events_path = directory / "events.jsonl"
    with events_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\n")
    return events_path


def load_events(session_id: str) -> list[dict]:
    events_path = session_dir(session_id) / "events.jsonl"
    if not events_path.exists():
        return []
    events: list[dict] = []
    for line in events_path.read_text(encoding="utf-8").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    return events


def valid_receipt(data: object) -> dict | None:
    if not isinstance(data, dict):
        return None
    if data.get("kind") != "bugfix_spec_created":
        return None
    if data.get("terminalState") != "spec_valid":
        return None
    if not data.get("traceId") or not data.get("specPath"):
        return None
    return data


def find_receipt(events: list[dict]) -> dict | None:
    for event in reversed(events):
        receipt = valid_receipt(event.get("receipt"))
        if receipt:
            return receipt

    candidates: list[Path] = []
    if INTAKE_DIR.exists():
        for path in INTAKE_DIR.glob("*/receipt.json"):
            if "sessions" not in path.parts:
                candidates.append(path)
    for path in sorted(candidates, key=lambda item: item.stat().st_mtime, reverse=True):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        receipt = valid_receipt(data)
        if receipt:
            return receipt
    return None


def write_unfinished_draft(directory: Path, summary: dict) -> None:
    prompt = summary.get("lastPromptSummary") or "No prompt text captured."
    draft = f"""# Unfinished Bugfix Intake

Session: {summary["sessionId"]}
Created at: {summary["createdAt"]}
Terminal state: unfinished_intake

## Last Captured Prompt
{prompt}

## Follow-up
Run `python3 scripts/intake/bugfix_spec.py new` to turn this abandoned intake into a validated SPEC.md.
"""
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "unfinished-intake.md").write_text(draft, encoding="utf-8")


def write_summary(stop_event: dict) -> Path:
    current_session_id = str(stop_event["session_id"])
    events = load_events(current_session_id)
    receipt = find_receipt(events)
    prompts = [event.get("promptSummary") for event in events if event.get("promptSummary")]
    summary = {
        "schemaVersion": 1,
        "kind": "bugfix_session_summary",
        "sessionId": current_session_id,
        "createdAt": utc_now(),
        "sourceTool": stop_event.get("sourceTool", "manual"),
        "eventCount": len(events),
        "terminalState": "spec_valid" if receipt else "unfinished_intake",
    }
    if prompts:
        summary["lastPromptSummary"] = prompts[-1]
    if receipt:
        summary["receipt"] = receipt
    directory = session_dir(current_session_id)
    directory.mkdir(parents=True, exist_ok=True)
    summary_path = directory / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not receipt:
        write_unfinished_draft(directory, summary)
    return summary_path


def run(args: argparse.Namespace) -> int:
    payload = load_payload()
    event = build_event(args.hook_event, payload)
    append_event(event)
    if args.hook_event == "stop":
        write_summary(event)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Capture optional bugfix intake session hook events.")
    parser.add_argument("hook_event", choices=["user-prompt-submit", "post-tool-use", "stop"])
    parser.set_defaults(func=run)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
