"""Unit tests for cabinet_ingest.py — parser shape and snapshot serialization."""

from __future__ import annotations

import json
import unittest

from cabinet_ingest import (
    CabinetEntry,
    build_snapshot,
    mandate_letters_available,
    parse_cabinet_html,
    snapshot_to_json,
    split_name,
)


SAMPLE_HTML = """
<html><body>
  <ul class="cabinet-list">
    <li><h2>Mark Carney</h2><p>Prime Minister of Canada</p></li>
    <li><h2>François-Philippe Champagne</h2><p>Minister of Finance and National Revenue</p></li>
    <li><h2>David J. McGuinty</h2><p>Minister of National Defence</p></li>
  </ul>
  <h3>Footer</h3>
  <p>Some unrelated text without the keyword.</p>
</body></html>
"""


class SplitNameTests(unittest.TestCase):
    def test_two_parts(self) -> None:
        self.assertEqual(split_name("Mark Carney"), ("Mark", "Carney"))

    def test_three_parts(self) -> None:
        self.assertEqual(split_name("David J. McGuinty"), ("David J.", "McGuinty"))

    def test_hyphenated_given_name(self) -> None:
        self.assertEqual(split_name("François-Philippe Champagne"), ("François-Philippe", "Champagne"))


class ParseCabinetHtmlTests(unittest.TestCase):
    def test_extracts_minister_entries(self) -> None:
        entries = parse_cabinet_html(SAMPLE_HTML)
        self.assertEqual(len(entries), 3)
        carney = entries[0]
        self.assertEqual(carney.minister_name, "Mark Carney")
        self.assertTrue(carney.is_prime_minister)
        finance = entries[1]
        self.assertEqual(finance.last_name, "Champagne")
        self.assertFalse(finance.is_prime_minister)
        self.assertIn("Finance", finance.portfolio)

    def test_skips_non_minister_sections(self) -> None:
        entries = parse_cabinet_html(SAMPLE_HTML)
        names = {entry.minister_name for entry in entries}
        self.assertNotIn("Footer", names)


class MandateLettersAvailableTests(unittest.TestCase):
    def test_not_available_when_explicit_message(self) -> None:
        html = "<html><body>There are currently no mandate letters available.</body></html>"
        self.assertFalse(mandate_letters_available(html))

    def test_available_when_links_present(self) -> None:
        html = '<html><body><a href="/mandate-letter-pm">Mandate letter</a></body></html>'
        self.assertTrue(mandate_letters_available(html))


class SnapshotSerializationTests(unittest.TestCase):
    def test_camel_case_ios_keys(self) -> None:
        entries = [
            CabinetEntry(
                minister_name="Mark Carney",
                first_name="Mark",
                last_name="Carney",
                portfolio="Prime Minister of Canada",
                is_prime_minister=True,
            )
        ]
        snapshot = build_snapshot(entries, letters_available=False)
        payload = json.loads(snapshot_to_json(snapshot))
        self.assertEqual(payload["version"], 1)
        self.assertEqual(payload["positions"][0]["ministerName"], "Mark Carney")
        self.assertTrue(payload["positions"][0]["isPrimeMinister"])
        self.assertFalse(payload["mandateLettersIndex"]["available"])
        self.assertIn("note", payload["mandateLettersIndex"])


if __name__ == "__main__":
    unittest.main()
