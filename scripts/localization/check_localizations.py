#!/usr/bin/env python3
"""Audit iOS localization table coverage.

The script intentionally exits successfully by default so CI can surface
localization drift as warnings before turning this into a hard gate.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


STRING_ENTRY_RE = re.compile(
    r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;',
    re.MULTILINE,
)
LOCALIZED_CALL_RES = [
    re.compile(r'\bNSLocalizedString\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\bString\s*\(\s*localized:\s*"((?:\\.|[^"\\])*)"'),
]


def unescape(value: str) -> str:
    def replace_unicode_brace(match: re.Match[str]) -> str:
        return chr(int(match.group(1), 16))

    value = re.sub(r"\\u\{([0-9a-fA-F]+)\}", replace_unicode_brace, value)
    replacements = {
        r"\\": "\\",
        r"\"": '"',
        r"\n": "\n",
        r"\r": "\r",
        r"\t": "\t",
        r"\0": "\0",
    }
    for escaped, replacement in replacements.items():
        value = value.replace(escaped, replacement)
    return value


def parse_strings_file(path: Path) -> tuple[dict[str, str], list[str]]:
    text = path.read_text(encoding="utf-8")
    entries: dict[str, str] = {}
    duplicates: list[str] = []
    for match in STRING_ENTRY_RE.finditer(text):
        key = unescape(match.group(1))
        value = unescape(match.group(2))
        if key in entries:
            duplicates.append(key)
        entries[key] = value
    return entries, duplicates


def extract_localized_keys(source_root: Path) -> set[str]:
    keys: set[str] = set()
    for swift_file in sorted(source_root.rglob("*.swift")):
        text = strip_swift_comments(swift_file.read_text(encoding="utf-8"))
        for pattern in LOCALIZED_CALL_RES:
            for match in pattern.finditer(text):
                keys.add(unescape(match.group(1)))
    return keys


def strip_swift_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//.*", "", text)


def github_warning(message: str) -> None:
    escaped = message.replace("%", "%25").replace("\n", "%0A").replace("\r", "%0D")
    print(f"::warning::{escaped}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path("ios/epac"))
    parser.add_argument("--english", type=Path, default=Path("ios/epac/en.lproj/Localizable.strings"))
    parser.add_argument("--french", type=Path, default=Path("ios/epac/fr.lproj/Localizable.strings"))
    parser.add_argument("--github-warnings", action="store_true")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero when gaps are found")
    args = parser.parse_args()

    english, english_duplicates = parse_strings_file(args.english)
    french, french_duplicates = parse_strings_file(args.french)
    source_keys = extract_localized_keys(args.source_root)

    missing_english = sorted(source_keys - set(english))
    missing_french_from_source = sorted(source_keys - set(french))
    missing_french_from_english = sorted(set(english) - set(french))
    extra_french = sorted(set(french) - set(english))

    coverage = 100.0 if not english else (len(set(english) & set(french)) / len(english)) * 100

    print("Localization coverage audit")
    print(f"- Source NSLocalizedString/String(localized:) keys: {len(source_keys)}")
    print(f"- English Localizable.strings keys: {len(english)}")
    print(f"- French Localizable.strings keys: {len(french)}")
    print(f"- French coverage of English table: {coverage:.1f}%")
    print(f"- Missing English keys used by source: {len(missing_english)}")
    print(f"- Missing French keys used by source: {len(missing_french_from_source)}")
    print(f"- Missing French keys present in English table: {len(missing_french_from_english)}")
    print(f"- French-only keys: {len(extra_french)}")

    warnings: list[str] = []
    for key in missing_english:
        warnings.append(f"Missing English localization for source key: {key}")
    for key in missing_french_from_source:
        warnings.append(f"Missing French localization for source key: {key}")
    for key in english_duplicates:
        warnings.append(f"Duplicate English localization key: {key}")
    for key in french_duplicates:
        warnings.append(f"Duplicate French localization key: {key}")

    if missing_french_from_english:
        print("\nFrench table is missing these English keys:")
        for key in missing_french_from_english:
            print(f"- {key}")

    if warnings:
        print("\nWarnings:")
        for warning in warnings:
            print(f"- {warning}")
            if args.github_warnings:
                github_warning(warning)

    if args.strict and (warnings or missing_french_from_english):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
