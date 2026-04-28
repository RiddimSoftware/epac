#!/usr/bin/env python3
"""Fetch the current federal Cabinet from pm.gc.ca and emit cabinet-positions.json.

Source pages (authoritative, official):
- https://www.pm.gc.ca/en/cabinet
- https://www.pm.gc.ca/en/mandate-letters

The output JSON is consumed by the iOS app (ios/epac/cabinet-positions.json) as a
bundled snapshot. Re-run this script after every Cabinet shuffle and commit the
updated file alongside the iOS PR that ships it to users.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from datetime import date
from html.parser import HTMLParser
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PM_CABINET_URL = "https://www.pm.gc.ca/en/cabinet"
PM_MANDATE_LETTERS_URL = "https://www.pm.gc.ca/en/mandate-letters"


@dataclass
class CabinetEntry:
    minister_name: str
    first_name: str
    last_name: str
    portfolio: str
    is_prime_minister: bool = False
    mandate_letter_url: Optional[str] = None


@dataclass
class CabinetSnapshot:
    version: int = 1
    as_of_date: str = ""
    source: dict = field(default_factory=dict)
    mandate_letters_index: dict = field(default_factory=dict)
    positions: list = field(default_factory=list)


class _CabinetParser(HTMLParser):
    """Extracts (name, portfolio) tuples from pm.gc.ca/en/cabinet.

    The page uses a card layout where each minister is in a list item with the
    name in an h2/h3 followed by a paragraph for the portfolio. The parser
    collects text in a state machine — heading text → name; following paragraph
    → portfolio — until it sees the next heading.
    """

    def __init__(self) -> None:
        super().__init__()
        self.entries: list[tuple[str, str]] = []
        self._mode: str = "idle"  # idle | name | portfolio
        self._current_name: list[str] = []
        self._current_portfolio: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        # Names appear in h2/h3 within the listing; portfolio in the immediate p.
        if tag in ("h2", "h3"):
            self._flush()
            self._mode = "name"
        elif tag == "p" and self._current_name and self._mode != "portfolio":
            self._mode = "portfolio"

    def handle_endtag(self, tag: str) -> None:
        if tag in ("h2", "h3") and self._mode == "name":
            self._mode = "idle"
        elif tag == "p" and self._mode == "portfolio":
            self._mode = "idle"

    def handle_data(self, data: str) -> None:
        text = data.strip()
        if not text:
            return
        if self._mode == "name":
            self._current_name.append(text)
        elif self._mode == "portfolio":
            self._current_portfolio.append(text)

    def _flush(self) -> None:
        if self._current_name and self._current_portfolio:
            name = re.sub(r"\s+", " ", " ".join(self._current_name)).strip()
            portfolio = re.sub(r"\s+", " ", " ".join(self._current_portfolio)).strip()
            if name and portfolio:
                self.entries.append((name, portfolio))
        self._current_name = []
        self._current_portfolio = []

    def close(self) -> None:  # type: ignore[override]
        self._flush()
        super().close()


def _fetch(url: str, timeout: int = 30) -> str:
    request = Request(url, headers={"User-Agent": "epac-ingest/1.0"})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def split_name(full_name: str) -> tuple[str, str]:
    """Split "First [Middle] Last" into (first_name, last_name).

    pm.gc.ca formats names with given name first; some include middle initials
    or middle names ("David J. McGuinty", "Lena Metlege Diab"). The iOS lookup
    matches by lastName, so collapsing the middle into the first name is fine.
    """
    parts = full_name.split()
    if len(parts) <= 1:
        return full_name, ""
    return " ".join(parts[:-1]), parts[-1]


def parse_cabinet_html(html: str) -> list[CabinetEntry]:
    parser = _CabinetParser()
    parser.feed(html)
    parser.close()

    entries: list[CabinetEntry] = []
    for raw_name, portfolio in parser.entries:
        if "minister" not in portfolio.lower() and "prime minister" not in portfolio.lower():
            # Filters out unrelated h2/h3 sections (e.g. site nav, footer).
            continue
        first_name, last_name = split_name(raw_name)
        is_pm = portfolio.strip().lower().startswith("prime minister")
        entries.append(CabinetEntry(
            minister_name=raw_name,
            first_name=first_name,
            last_name=last_name,
            portfolio=portfolio,
            is_prime_minister=is_pm,
        ))
    return entries


def mandate_letters_available(html: str) -> bool:
    """Detect whether the mandate-letters page lists any letters at all."""
    text = re.sub(r"<[^>]+>", " ", html).lower()
    if "no mandate letters" in text:
        return False
    return "mandate letter" in text


def build_snapshot(entries: list[CabinetEntry], letters_available: bool) -> CabinetSnapshot:
    return CabinetSnapshot(
        version=1,
        as_of_date=date.today().isoformat(),
        source={"title": "Prime Minister's Office", "url": PM_CABINET_URL},
        mandate_letters_index={
            "url": PM_MANDATE_LETTERS_URL,
            "available": letters_available,
            "note": (
                None if letters_available
                else "The Prime Minister's Office has not yet published mandate letters for this cabinet. Check back at the URL above."
            ),
        },
        positions=[asdict(entry) for entry in entries],
    )


def snapshot_to_json(snapshot: CabinetSnapshot) -> str:
    payload = {
        "version": snapshot.version,
        "asOfDate": snapshot.as_of_date,
        "source": snapshot.source,
        "mandateLettersIndex": {
            "url": snapshot.mandate_letters_index["url"],
            "available": snapshot.mandate_letters_index["available"],
            **({"note": snapshot.mandate_letters_index["note"]} if snapshot.mandate_letters_index.get("note") else {}),
        },
        "positions": [
            {
                "ministerName": entry["minister_name"],
                "firstName": entry["first_name"],
                "lastName": entry["last_name"],
                "portfolio": entry["portfolio"],
                **({"isPrimeMinister": True} if entry["is_prime_minister"] else {}),
                "mandateLetterURL": entry["mandate_letter_url"],
            }
            for entry in snapshot.positions
        ],
    }
    return json.dumps(payload, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="ios/epac/cabinet-positions.json",
        help="Path to write the JSON snapshot (default: ios/epac/cabinet-positions.json)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the snapshot to stdout instead of writing it",
    )
    args = parser.parse_args(argv)

    try:
        cabinet_html = _fetch(PM_CABINET_URL)
        letters_html = _fetch(PM_MANDATE_LETTERS_URL)
    except (HTTPError, URLError) as error:
        print(f"ERROR: failed to fetch from pm.gc.ca: {error}", file=sys.stderr)
        return 2

    entries = parse_cabinet_html(cabinet_html)
    if not entries:
        print(
            "ERROR: parsed zero cabinet entries — pm.gc.ca markup may have changed; "
            "update _CabinetParser before re-running.",
            file=sys.stderr,
        )
        return 3

    snapshot = build_snapshot(entries, mandate_letters_available(letters_html))
    payload = snapshot_to_json(snapshot)

    if args.dry_run:
        sys.stdout.write(payload)
    else:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(payload)
        print(f"Wrote {len(entries)} cabinet positions to {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
