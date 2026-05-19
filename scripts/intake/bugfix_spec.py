#!/usr/bin/env python3
"""Create and validate bugfix SPEC.md files for the epac factory intake path."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = ROOT / ".factory" / "intake"
TARGET_REPO = "RiddimSoftware/epac"

REQUIRED_SECTIONS = [
    "## Original Prompt",
    "## Problem",
    "### Observed Behavior",
    "### Expected Behavior",
    "## Reproduction Steps",
    "## Acceptance Criteria",
    "## Evidence Plan",
    "## Validation Plan",
    "## Non-goals",
    "## Provenance",
    "## Next Steps",
]

REQUIRED_FIELD_LABELS = [
    "Trace ID",
    "Reporter",
    "Source",
    "Created at",
    "Target repo",
    "Affected surface",
]

PLACEHOLDER_RE = re.compile(r"\b(TBD|TODO|FIXME)\b|\[[^\]]+\](?!\()", re.IGNORECASE)


@dataclass(frozen=True)
class BugfixSpecInput:
    title: str
    reporter: str
    source: str
    surface: str
    observed: str
    expected: str
    steps: list[str]
    evidence: str
    validation: str
    original_prompt: str
    non_goals: str
    trace_id: str
    created_at: str
    source_tool: str
    session_id: str


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:64] or "bugfix"


def prompt_for(label: str) -> str:
    value = input(f"{label}: ").strip()
    while not value:
        print(f"{label} is required.", file=sys.stderr)
        value = input(f"{label}: ").strip()
    return value


def collect_steps(args: argparse.Namespace) -> list[str]:
    steps = list(args.step or [])
    if steps:
        return [step.strip() for step in steps if step.strip()]
    if not sys.stdin.isatty():
        return []

    print("Reproduction steps. Enter one per line; submit an empty line to finish.")
    collected: list[str] = []
    while True:
        value = input(f"Step {len(collected) + 1}: ").strip()
        if not value:
            break
        collected.append(value)
    return collected


def value_or_prompt(args: argparse.Namespace, attr: str, label: str) -> str:
    value = getattr(args, attr)
    if value:
        return value.strip()
    if sys.stdin.isatty():
        return prompt_for(label)
    return ""


def build_input(args: argparse.Namespace) -> BugfixSpecInput:
    title = value_or_prompt(args, "title", "Bug title")
    reporter = value_or_prompt(args, "reporter", "Reporter")
    source = value_or_prompt(args, "source", "Source session or issue")
    surface = value_or_prompt(args, "surface", "Affected app surface")
    observed = value_or_prompt(args, "observed", "Observed behavior")
    expected = value_or_prompt(args, "expected", "Expected behavior")
    evidence = value_or_prompt(args, "evidence", "Required evidence")
    validation = value_or_prompt(args, "validation", "Reporter/TestFlight validation")
    steps = collect_steps(args)

    missing = [
        name
        for name, value in [
            ("--title", title),
            ("--reporter", reporter),
            ("--source", source),
            ("--surface", surface),
            ("--observed", observed),
            ("--expected", expected),
            ("--evidence", evidence),
            ("--validation", validation),
        ]
        if not value
    ]
    if not steps:
        missing.append("--step")
    if missing:
        raise ValueError(
            "missing required bugfix intake fields: "
            + ", ".join(missing)
            + ". Re-run interactively or pass them as flags."
        )

    now = datetime.now(UTC)
    trace_id = args.trace_id or f"BUGFIX-{now.strftime('%Y%m%d-%H%M%S')}-{uuid4().hex[:8]}"
    original_prompt = args.original_prompt.strip() if args.original_prompt else observed
    non_goals = args.non_goals.strip() if args.non_goals else "Do not implement unrelated UI, backend, or release changes."
    source_tool = (args.source_tool or os.environ.get("BUGFIX_SOURCE_TOOL") or "").strip()
    session_id = (args.session_id or os.environ.get("BUGFIX_SESSION_ID") or "").strip()

    return BugfixSpecInput(
        title=title,
        reporter=reporter,
        source=source,
        surface=surface,
        observed=observed,
        expected=expected,
        steps=steps,
        evidence=evidence,
        validation=validation,
        original_prompt=original_prompt,
        non_goals=non_goals,
        trace_id=trace_id,
        created_at=now.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        source_tool=source_tool,
        session_id=session_id,
    )


def render_spec(spec: BugfixSpecInput) -> str:
    steps = "\n".join(f"{index}. {step}" for index, step in enumerate(spec.steps, start=1))
    first_sentence = spec.expected.rstrip(".")
    return f"""# Bugfix SPEC: {spec.title}

Trace ID: {spec.trace_id}
Reporter: {spec.reporter}
Source: {spec.source}
Created at: {spec.created_at}
Target repo: {TARGET_REPO}
Affected surface: {spec.surface}

## Original Prompt
{spec.original_prompt}

## Problem
This bugfix SPEC turns a contributor or LLM-session report into a factory-ready work contract. Implementation must not begin until this SPEC validates.

### Observed Behavior
{spec.observed}

### Expected Behavior
{spec.expected}

## Reproduction Steps
{steps}

## Acceptance Criteria
- Given the {spec.surface} is visible
  When the reporter follows the reproduction steps
  Then the app shows: {first_sentence}.
- Given the fix has been implemented
  When the evidence plan is run
  Then the generated artifacts show the expected behavior and do not show the observed bug.
- Given a TestFlight or local validation build is available
  When the reporter validates the affected surface
  Then their approval or blocker is recorded before release promotion.

## Evidence Plan
{spec.evidence}

Minimum artifact requirements:
- before screenshot or video showing the observed behavior, if reproducible before the fix
- after screenshot or video showing the expected behavior
- manifest linking this SPEC, the implementation PR, commit SHA, app build, and validation result

## Validation Plan
{spec.validation}

## Non-goals
{spec.non_goals}

## Provenance
- Intake kind: bugfix
- Trace ID: {spec.trace_id}
- Reporter: {spec.reporter}
- Source: {spec.source}
- Created at: {spec.created_at}
- Target repo: {TARGET_REPO}

## Next Steps
- Attach this SPEC to the GitHub or Linear issue.
- Link the implementation PR back to this SPEC.
- Generate evidence before release promotion.
"""


def default_output_path(title: str) -> Path:
    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    return DEFAULT_OUT_DIR / f"{stamp}-{slugify(title)}" / "SPEC.md"


def write_receipt(spec: BugfixSpecInput, spec_path: Path) -> Path:
    receipt = {
        "schemaVersion": 1,
        "kind": "bugfix_spec_created",
        "traceId": spec.trace_id,
        "repo": TARGET_REPO,
        "specPath": str(spec_path),
        "createdAt": spec.created_at,
        "reporter": spec.reporter,
        "source": spec.source,
        "affectedSurface": spec.surface,
        "terminalState": "spec_valid",
    }
    if spec.source_tool:
        receipt["sourceTool"] = spec.source_tool
    if spec.session_id:
        receipt["sessionId"] = spec.session_id
    receipt_path = spec_path.with_name("receipt.json")
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return receipt_path


def write_spec(args: argparse.Namespace) -> int:
    try:
        spec = build_input(args)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    out = Path(args.out).expanduser() if args.out else default_output_path(spec.title)
    if out.exists() and not args.force:
        print(f"{out} already exists; pass --force to overwrite.", file=sys.stderr)
        return 2
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render_spec(spec), encoding="utf-8")
    print(f"Wrote bugfix SPEC: {out}")
    validation_errors = validate_text(out.read_text(encoding="utf-8"))
    if validation_errors:
        for error in validation_errors:
            print(error, file=sys.stderr)
        return 1
    receipt = write_receipt(spec, out)
    print(f"Wrote bugfix intake receipt: {receipt}")
    print(f"valid bugfix SPEC: {out}")
    return 0


def has_nonempty_field(text: str, label: str) -> bool:
    match = re.search(rf"^{re.escape(label)}:\s*(.+)$", text, re.MULTILINE)
    return bool(match and match.group(1).strip())


def section_body(text: str, heading: str) -> str:
    pattern = re.compile(
        rf"^{re.escape(heading)}\s*$\n(?P<body>.*?)(?=^#{{1,6}}\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    return match.group("body").strip() if match else ""


def validate_text(text: str) -> list[str]:
    errors: list[str] = []
    if not text.startswith("# Bugfix SPEC: "):
        errors.append("missing required heading: # Bugfix SPEC: <title>")

    for label in REQUIRED_FIELD_LABELS:
        if not has_nonempty_field(text, label):
            errors.append(f"missing required field: {label}")

    for section in REQUIRED_SECTIONS:
        if section not in text:
            errors.append(f"missing required section: {section}")

    steps = re.findall(r"^\d+\.\s+\S", section_body(text, "## Reproduction Steps"), re.MULTILINE)
    if not steps:
        errors.append("missing at least one numbered reproduction step")

    criteria = re.findall(r"^- Given .+", section_body(text, "## Acceptance Criteria"), re.MULTILINE)
    if len(criteria) < 2:
        errors.append("missing at least two acceptance criteria starting with '- Given'")

    if PLACEHOLDER_RE.search(text):
        errors.append("SPEC contains placeholder text; replace TBD/TODO/FIXME/bracket placeholders before intake")

    return errors


def validate_spec(args: argparse.Namespace) -> int:
    path = Path(args.spec)
    if not path.exists():
        print(f"SPEC not found: {path}", file=sys.stderr)
        return 2
    errors = validate_text(path.read_text(encoding="utf-8"))
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"valid bugfix SPEC: {path}")
    return 0


def extract_title(text: str) -> str:
    match = re.search(r"^# Bugfix SPEC:\s*(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else "Bugfix intake"


def extract_field(text: str, label: str) -> str:
    match = re.search(rf"^{re.escape(label)}:\s*(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else ""


def extract_section(text: str, heading: str) -> str:
    body = section_body(text, heading)
    return body if body else "See linked SPEC."


def render_issue_body(spec_path: Path, text: str) -> str:
    title = extract_title(text)
    trace_id = extract_field(text, "Trace ID")
    surface = extract_field(text, "Affected surface")
    observed = extract_section(text, "### Observed Behavior")
    expected = extract_section(text, "### Expected Behavior")
    evidence = extract_section(text, "## Evidence Plan")
    validation = extract_section(text, "## Validation Plan")
    return f"""## Bugfix intake receipt
Spec: {spec_path}
Trace ID: {trace_id}
Affected surface: {surface}

## Summary
{title}

## Observed behavior
{observed}

## Expected behavior
{expected}

## Evidence plan
{evidence}

## Reporter validation
{validation}
"""


def issue_body(args: argparse.Namespace) -> int:
    path = Path(args.spec)
    if not path.exists():
        print(f"SPEC not found: {path}", file=sys.stderr)
        return 2
    text = path.read_text(encoding="utf-8")
    errors = validate_text(text)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(render_issue_body(path, text))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create and validate bugfix SPEC.md files before implementation starts."
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    new = subcommands.add_parser("new", help="Create a bugfix SPEC.md file.")
    new.add_argument("--title")
    new.add_argument("--reporter")
    new.add_argument("--source")
    new.add_argument("--surface")
    new.add_argument("--observed")
    new.add_argument("--expected")
    new.add_argument("--step", action="append", default=[])
    new.add_argument("--evidence")
    new.add_argument("--validation")
    new.add_argument("--original-prompt")
    new.add_argument("--non-goals")
    new.add_argument("--trace-id")
    new.add_argument("--source-tool")
    new.add_argument("--session-id")
    new.add_argument("--out")
    new.add_argument("--force", action="store_true")
    new.set_defaults(func=write_spec)

    validate = subcommands.add_parser("validate", help="Validate a bugfix SPEC.md file.")
    validate.add_argument("spec")
    validate.set_defaults(func=validate_spec)

    issue = subcommands.add_parser("issue-body", help="Render a GitHub/Linear issue body from a SPEC.md file.")
    issue.add_argument("spec")
    issue.set_defaults(func=issue_body)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
