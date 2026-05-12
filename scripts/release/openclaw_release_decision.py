#!/usr/bin/env python3
"""Render an OpenClaw release decision for epac App Store actions.

The evaluator is intentionally read-only: it consumes a repo-controlled policy
and a release-state JSON document, then prints a decision receipt. It never
uploads, submits, releases, pauses phased release, or edits App Store metadata.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

Decision = str
DECISION_ORDER: dict[Decision, int] = {
    "allow": 0,
    "wait": 1,
    "request_approval": 2,
    "escalate": 3,
    "block": 4,
}


@dataclass(frozen=True)
class ReleaseDecision:
    decision: Decision
    rule: str
    candidate_version: str
    candidate_build: str
    action: str
    source_of_truth: str
    previous_version: str | None
    previous_state: str | None
    previous_terminal_at: str | None
    elapsed_hours: float | None
    minimum_hours: int
    risk_signals: list[str]
    evidence: list[str]
    override: dict[str, Any] | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "decision": self.decision,
            "rule": self.rule,
            "candidateVersion": self.candidate_version,
            "candidateBuild": self.candidate_build,
            "action": self.action,
            "sourceOfTruth": self.source_of_truth,
            "previousVersion": self.previous_version,
            "previousState": self.previous_state,
            "previousTerminalAt": self.previous_terminal_at,
            "elapsedHours": self.elapsed_hours,
            "minimumHours": self.minimum_hours,
            "riskSignals": self.risk_signals,
            "evidence": self.evidence,
            "override": self.override,
        }


def parse_iso8601(value: str, field_name: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(f"{field_name} must be an ISO-8601 timestamp: {value}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"{field_name} must include a timezone: {value}")
    return parsed.astimezone(timezone.utc)


def load_json(path: str) -> dict[str, Any]:
    with Path(path).open() as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def most_severe(decisions: list[tuple[Decision, str]]) -> tuple[Decision, str]:
    return max(decisions, key=lambda item: DECISION_ORDER[item[0]])


def validate_override(
    policy: dict[str, Any],
    state: dict[str, Any],
    candidate_version: str,
    candidate_build: str,
) -> list[str]:
    override = state.get("override")
    if not override:
        return ["override receipt is absent"]
    if not isinstance(override, dict):
        return ["override receipt must be a JSON object"]

    errors: list[str] = []
    for field in policy.get("overrideRequiredFields", []):
        if not override.get(field):
            errors.append(f"override missing {field}")

    if override.get("candidateVersion") != candidate_version:
        errors.append("override candidateVersion does not match candidate")
    if str(override.get("candidateBuild")) != candidate_build:
        errors.append("override candidateBuild does not match candidate")
    if override.get("approvedAt"):
        try:
            parse_iso8601(str(override["approvedAt"]), "override.approvedAt")
        except ValueError as exc:
            errors.append(str(exc))
    return errors


def evaluate(policy: dict[str, Any], state: dict[str, Any]) -> ReleaseDecision:
    candidate_version = str(state.get("candidateVersion") or "").strip()
    candidate_build = str(state.get("candidateBuild") or "").strip()
    action = str(state.get("action") or "").strip()
    source = str(state.get("sourceOfTruth") or "").strip()

    if not candidate_version:
        raise ValueError("candidateVersion is required")
    if not candidate_build:
        raise ValueError("candidateBuild is required")
    if action not in policy.get("actions", {}):
        raise ValueError(f"action must be one of: {', '.join(sorted(policy.get('actions', {}).keys()))}")

    evaluated_at_raw = str(state.get("evaluatedAt") or datetime.now(timezone.utc).isoformat())
    evaluated_at = parse_iso8601(evaluated_at_raw, "evaluatedAt")
    action_policy = policy["actions"][action]
    minimum_hours = int(policy.get("minimumHoursAfterPreviousTerminalState", 24))
    risk_signals = [str(signal) for signal in state.get("riskSignals", [])]
    previous_version = state.get("previousVersion")
    previous_state = state.get("previousState")
    previous_terminal_at = (
        state.get("previousStateChangedAt")
        or state.get("previousReviewedAt")
        or state.get("previousReleasedAt")
    )

    evidence = [
        f"candidate {candidate_version} build {candidate_build}",
        f"action {action}",
        f"source {source or 'unspecified'}",
    ]
    gate_applies = bool(action_policy.get("requires24HourGate", False))
    decisions: list[tuple[Decision, str]] = []
    if not gate_applies:
        decisions.append((str(action_policy.get("defaultDecision", "allow")), f"action:{action}:default"))

    source_names = [entry.get("name") for entry in policy.get("sourceOfTruthOrder", [])]
    if source and source not in source_names:
        decisions.append(("block", "source_of_truth:unknown"))
        evidence.append(f"unknown source of truth {source}")

    for signal in risk_signals:
        outcome = policy.get("riskSignalOutcomes", {}).get(signal)
        if outcome:
            decisions.append((str(outcome), f"risk_signal:{signal}"))
            evidence.append(f"risk signal {signal} maps to {outcome}")
        else:
            decisions.append(("request_approval", f"risk_signal:{signal}:unknown"))
            evidence.append(f"unknown risk signal {signal} requires human approval")

    elapsed_hours: float | None = None
    terminal_states = set(policy.get("terminalPreviousVersionStates", []))

    if gate_applies:
        if not previous_version or not previous_state or not previous_terminal_at:
            decisions.append(("block", "24_hour_gate:missing_previous_version_evidence"))
            evidence.append("previous version, state, and terminal timestamp are required")
        elif previous_state not in terminal_states:
            decisions.append(("block", "24_hour_gate:previous_state_not_terminal"))
            evidence.append(f"previous state {previous_state} is not an accepted terminal state")
        else:
            terminal_at = parse_iso8601(str(previous_terminal_at), "previous terminal timestamp")
            elapsed_hours = round((evaluated_at - terminal_at).total_seconds() / 3600, 2)
            terminal_at_label = terminal_at.isoformat().replace("+00:00", "Z")
            evidence.append(f"previous {previous_version} reached {previous_state} at {terminal_at_label}")
            evidence.append(f"elapsed {elapsed_hours}h; minimum {minimum_hours}h")
            if elapsed_hours < 0:
                decisions.append(("block", "24_hour_gate:previous_timestamp_in_future"))
            elif elapsed_hours < minimum_hours:
                override_errors = validate_override(policy, state, candidate_version, candidate_build)
                if action == "emergency_hotfix_release" and not override_errors:
                    decisions.append(("allow", "24_hour_gate:emergency_override"))
                    evidence.append("valid emergency override bypasses 24-hour gate")
                elif state.get("override") and not override_errors:
                    decisions.append(
                        (
                            str(action_policy.get("overrideDecision", "request_approval")),
                            "24_hour_gate:human_override_requested",
                        )
                    )
                    evidence.append("valid human override receipt present")
                elif state.get("override"):
                    decisions.append(("block", "24_hour_gate:invalid_override"))
                    evidence.extend(override_errors)
                else:
                    decisions.append(("wait", "24_hour_gate:not_elapsed"))
            else:
                default_decision = str(action_policy.get("defaultDecision", "allow"))
                if default_decision in {"request_approval", "escalate", "block"}:
                    decisions.append((default_decision, f"action:{action}:default"))
                else:
                    decisions.append(("allow", "24_hour_gate:elapsed"))
    elif action == "phased_release_continue":
        evidence.append("phased release continuation requires human confirmation")

    if not decisions:
        decisions.append(("allow", "policy:default_allow"))
    decision, rule = most_severe(decisions)
    return ReleaseDecision(
        decision=decision,
        rule=rule,
        candidate_version=candidate_version,
        candidate_build=candidate_build,
        action=action,
        source_of_truth=source,
        previous_version=str(previous_version) if previous_version is not None else None,
        previous_state=str(previous_state) if previous_state is not None else None,
        previous_terminal_at=str(previous_terminal_at) if previous_terminal_at is not None else None,
        elapsed_hours=elapsed_hours,
        minimum_hours=minimum_hours,
        risk_signals=risk_signals,
        evidence=evidence,
        override=state.get("override") if isinstance(state.get("override"), dict) else None,
    )


def render_markdown(decision: ReleaseDecision) -> str:
    data = decision.as_dict()
    lines = [
        "# OpenClaw release decision",
        "",
        f"Decision: **{data['decision']}**",
        f"Policy rule: `{data['rule']}`",
        "",
        "## Evidence",
        f"- Candidate: {data['candidateVersion']} ({data['candidateBuild']})",
        f"- Action: `{data['action']}`",
        f"- Previous version: {data['previousVersion'] or 'unknown'}",
        f"- Previous state: {data['previousState'] or 'unknown'}",
        f"- Previous terminal timestamp: {data['previousTerminalAt'] or 'unknown'}",
        f"- Elapsed hours: {data['elapsedHours'] if data['elapsedHours'] is not None else 'unknown'}",
        f"- Minimum hours: {data['minimumHours']}",
        f"- Source of truth: `{data['sourceOfTruth'] or 'unspecified'}`",
        f"- Risk signals: {', '.join(data['riskSignals']) if data['riskSignals'] else 'none'}",
    ]
    if data["override"]:
        override = data["override"]
        lines.extend(
            [
                "",
                "## Override receipt",
                f"- Approved by: {override.get('approvedBy', 'unknown')}",
                f"- Approved at: {override.get('approvedAt', 'unknown')}",
                f"- Reason: {override.get('reason', 'unknown')}",
                f"- Public audit note: {override.get('publicAuditNote', 'unknown')}",
            ]
        )
    lines.extend(["", "## Rule trace"])
    lines.extend(f"- {item}" for item in data["evidence"])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", required=True, help="Path to release-decision-policy.json")
    parser.add_argument("--input", required=True, help="Path to release-state JSON")
    parser.add_argument("--format", choices=["json", "markdown"], default="json")
    parser.add_argument(
        "--fail-closed",
        action="store_true",
        help="Exit non-zero for wait/request_approval/escalate/block decisions.",
    )
    args = parser.parse_args()

    try:
        decision = evaluate(load_json(args.policy), load_json(args.input))
    except Exception as exc:  # noqa: BLE001 - CLI should render policy errors plainly.
        print(f"OpenClaw policy error: {exc}", file=sys.stderr)
        return 2

    if args.format == "markdown":
        print(render_markdown(decision), end="")
    else:
        print(json.dumps(decision.as_dict(), indent=2, sort_keys=True))

    if args.fail_closed and decision.decision != "allow":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
