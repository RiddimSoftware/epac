#!/usr/bin/env python3
"""
Extract ``Reporter-Email:`` addresses from PR descriptions.

Reads a space-separated list of PR numbers from ``--prs``, fetches each PR
body via ``gh pr view``, and collects unique email addresses found on lines
matching ``Reporter-Email: <address>``.

Writes two GitHub Actions output variables:
  emails   - comma-separated unique email list (empty string when none found)
  entries  - JSON array of {"email": "...", "issue": "<PR-number>"} objects,
             one per unique email (de-duplicated; first PR wins for issue ref)

Usage:
  python3 scripts/release/extract_reporter_emails.py --prs "42 43 44"
"""
import argparse
import json
import re
import subprocess
import sys
import os


MARKER_PATTERN = re.compile(r"^Reporter-Email:\s*(\S+@\S+)\s*$", re.IGNORECASE | re.MULTILINE)


def gh_pr_body(pr_number: str) -> str:
    result = subprocess.run(
        ["gh", "pr", "view", pr_number, "--json", "body", "--jq", ".body"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Warning: could not fetch PR #{pr_number}: {result.stderr}", file=sys.stderr)
        return ""
    return result.stdout


def extract_emails_from_body(body: str) -> list[str]:
    return MARKER_PATTERN.findall(body)


def set_github_output(name: str, value: str) -> None:
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            f.write(f"{name}={value}\n")
    else:
        print(f"GITHUB_OUTPUT not set; would write: {name}={value}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prs", default="", help="Space-separated PR numbers")
    args = parser.parse_args()

    pr_numbers = args.prs.split() if args.prs.strip() else []

    seen_emails: set[str] = set()
    entries: list[dict] = []

    for pr_num in pr_numbers:
        body = gh_pr_body(pr_num)
        emails = extract_emails_from_body(body)
        for email in emails:
            if email not in seen_emails:
                seen_emails.add(email)
                entries.append({"email": email, "issue": pr_num})
                print(f"PR #{pr_num}: found reporter {email}", file=sys.stderr)

    emails_csv = ",".join(e["email"] for e in entries)
    entries_json = json.dumps(entries)

    print(f"Total unique reporters: {len(entries)}", file=sys.stderr)

    set_github_output("emails", emails_csv)
    set_github_output("entries", entries_json)


if __name__ == "__main__":
    main()
