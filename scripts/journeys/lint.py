#!/usr/bin/env python3
"""
Journey catalogue lint script.

Walks docs/journeys/**/*.feature, parses each file with gherkin-official, and
validates the tag conventions defined in docs/journeys/SCHEMA.md.

Exit codes:
  0 — no violations (warnings are printed but do not affect exit code)
  1 — one or more Scenario-level violations found

Output format for errors and warnings:
  <file>:<line>: [error|warning] <message>
"""

import os
import re
import sys
from pathlib import Path

try:
    from gherkin.parser import Parser
    from gherkin.token_scanner import TokenScanner
    from gherkin.errors import ParserError
except ImportError:
    print("error: gherkin-official is not installed. Run: pip install gherkin-official", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Controlled vocabularies
# ---------------------------------------------------------------------------

TAB_ENUM = {"home", "parliament", "members", "accountability", "search", "cross-cutting"}

STATE_VOCAB = {"loading", "loaded", "empty", "error", "offline", "rate-limited"}

SCREEN_KEBAB_RE = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
TICKET_RE = re.compile(r'^EPAC-\d+$')


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def feature_files(root: Path):
    """Yield all .feature files under *root*."""
    for path in sorted(root.rglob("*.feature")):
        yield path


def folder_tab(feature_path: Path, journeys_root: Path) -> str:
    """Return the direct child directory of journeys_root that contains *feature_path*."""
    rel = feature_path.relative_to(journeys_root)
    return rel.parts[0]


def parse_tags(tag_list: list) -> dict:
    """
    Given a list of gherkin tag dicts (each with a 'name' key like '@tab:home'),
    return a dict mapping prefix -> list of (value, line) tuples.
    Unknown tags are stored under the key None.
    """
    result: dict = {}
    for tag in tag_list:
        name: str = tag["name"]
        line: int = tag.get("location", {}).get("line", 0)

        if name.startswith("@tab:"):
            result.setdefault("tab", []).append((name[len("@tab:"):], line))
        elif name.startswith("@screen:"):
            result.setdefault("screen", []).append((name[len("@screen:"):], line))
        elif name.startswith("@state:"):
            result.setdefault("state", []).append((name[len("@state:"):], line))
        elif name.startswith("@ticket:"):
            result.setdefault("ticket", []).append((name[len("@ticket:"):], line))
        elif name.startswith("@pr:"):
            result.setdefault("pr", []).append((name[len("@pr:"):], line))
        elif name == "@legacy":
            result.setdefault("legacy", []).append((True, line))
        elif name == "@draft":
            result.setdefault("draft", []).append((True, line))
        else:
            result.setdefault(None, []).append((name, line))

    return result


# ---------------------------------------------------------------------------
# Main lint logic
# ---------------------------------------------------------------------------

def lint_file(feature_path: Path, journeys_root: Path) -> tuple[list[str], list[str]]:
    """
    Lint a single .feature file.

    Returns (errors, warnings) — each item is a formatted 'file:line: message' string.
    """
    errors: list[str] = []
    warnings: list[str] = []

    def err(line, msg):
        errors.append(f"{feature_path}:{line}: error: {msg}")

    def warn(line, msg):
        warnings.append(f"{feature_path}:{line}: warning: {msg}")

    # Determine expected @tab: value from folder
    expected_tab = folder_tab(feature_path, journeys_root)

    # Parse the feature file
    try:
        source = feature_path.read_text(encoding="utf-8")
        parser = Parser()
        doc = parser.parse(TokenScanner(source))
    except ParserError as exc:
        errors.append(f"{feature_path}:1: error: gherkin parse error: {exc}")
        return errors, warnings

    feature = doc.get("feature")
    if not feature:
        return errors, warnings

    children = feature.get("children", [])

    for child in children:
        scenario = child.get("scenario")
        if not scenario:
            continue

        sc_line = scenario.get("location", {}).get("line", 0)
        tags = parse_tags(scenario.get("tags", []))

        # --- @tab: ---
        tab_values = tags.get("tab", [])
        if len(tab_values) == 0:
            err(sc_line, "Scenario is missing required @tab: tag")
        elif len(tab_values) > 1:
            err(sc_line, f"Scenario has {len(tab_values)} @tab: tags; exactly one is required")
        else:
            tab_val, tab_line = tab_values[0]
            if tab_val not in TAB_ENUM:
                err(tab_line, f"@tab:{tab_val!r} is not in the allowed enum {sorted(TAB_ENUM)}")
            elif tab_val != expected_tab:
                err(tab_line, f"@tab:{tab_val!r} does not match parent folder {expected_tab!r}")

        # --- @screen: ---
        screen_values = tags.get("screen", [])
        if len(screen_values) == 0:
            err(sc_line, "Scenario is missing required @screen: tag")
        elif len(screen_values) > 1:
            err(sc_line, f"Scenario has {len(screen_values)} @screen: tags; exactly one is required")
        else:
            screen_val, screen_line = screen_values[0]
            if not SCREEN_KEBAB_RE.match(screen_val):
                err(screen_line, f"@screen:{screen_val!r} is not kebab-case (lowercase letters, digits, hyphens only)")

        # --- @state: ---
        state_values = tags.get("state", [])
        if len(state_values) == 0:
            err(sc_line, "Scenario is missing required @state: tag")
        elif len(state_values) > 1:
            err(sc_line, f"Scenario has {len(state_values)} @state: tags; exactly one is required")
        else:
            state_val, state_line = state_values[0]
            if state_val not in STATE_VOCAB:
                err(state_line, f"@state:{state_val!r} is not in the controlled vocabulary {sorted(STATE_VOCAB)}")

        # --- @ticket: / @legacy / @draft ---
        ticket_values = tags.get("ticket", [])
        has_legacy = bool(tags.get("legacy"))
        has_draft = bool(tags.get("draft"))

        if not ticket_values and not has_legacy and not has_draft:
            warn(sc_line, "Scenario has no @ticket:EPAC-N tag and no @legacy flag; add a ticket link or @legacy/@draft")
        else:
            for ticket_val, ticket_line in ticket_values:
                if not TICKET_RE.match(ticket_val):
                    err(ticket_line, f"@ticket:{ticket_val!r} does not match expected format EPAC-<digits>")

    return errors, warnings


def coverage_summary(feature_path: Path, journeys_root: Path) -> dict:
    """
    Returns a dict mapping screen -> set of states for coverage tracking.
    Silently skips files that fail to parse (lint_file handles those errors).
    """
    coverage: dict = {}
    try:
        source = feature_path.read_text(encoding="utf-8")
        parser = Parser()
        doc = parser.parse(TokenScanner(source))
    except Exception:
        return coverage

    feature = doc.get("feature")
    if not feature:
        return coverage

    for child in feature.get("children", []):
        scenario = child.get("scenario")
        if not scenario:
            continue
        tags = parse_tags(scenario.get("tags", []))
        screen_values = tags.get("screen", [])
        state_values = tags.get("state", [])
        if screen_values and state_values:
            screen = screen_values[0][0]
            state = state_values[0][0]
            coverage.setdefault(screen, set()).add(state)

    return coverage


def print_coverage(all_coverage: dict) -> None:
    """Print a human-readable tag-coverage summary."""
    if not all_coverage:
        print("\nTag-coverage summary: (no scenarios found)")
        return

    print("\nTag-coverage summary:")
    print(f"  {'Screen':<40} {'Covered states':<50} Missing")
    print(f"  {'-'*40} {'-'*50} -------")
    for screen in sorted(all_coverage):
        covered = sorted(all_coverage[screen])
        missing = sorted(STATE_VOCAB - all_coverage[screen])
        covered_str = ", ".join(covered) if covered else "(none)"
        missing_str = ", ".join(missing) if missing else "(none)"
        print(f"  {screen:<40} {covered_str:<50} {missing_str}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    journeys_root = repo_root / "docs" / "journeys"

    if not journeys_root.exists():
        print(f"No docs/journeys/ directory found at {journeys_root}; nothing to lint.")
        return 0

    files = list(feature_files(journeys_root))

    if not files:
        print("No .feature files found; nothing to lint.")
        return 0

    all_errors: list[str] = []
    all_warnings: list[str] = []
    all_coverage: dict = {}

    for fpath in files:
        errors, warnings = lint_file(fpath, journeys_root)
        all_errors.extend(errors)
        all_warnings.extend(warnings)

        cov = coverage_summary(fpath, journeys_root)
        for screen, states in cov.items():
            all_coverage.setdefault(screen, set()).update(states)

    for msg in all_warnings:
        print(msg)

    for msg in all_errors:
        print(msg)

    print_coverage(all_coverage)

    if all_errors:
        print(f"\n{len(all_errors)} error(s), {len(all_warnings)} warning(s).")
        return 1

    print(f"\n0 errors, {len(all_warnings)} warning(s). Lint passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
