"""Unit tests for subject_matters_ingest.py — parser shape and report rendering."""

from __future__ import annotations

import unittest

from subject_matters_ingest import (
    OCLSubjectMatter,
    build_mapping_report,
    merge_bilingual,
    parse_communication_counts,
    parse_subject_labels,
)


# Trimmed but structurally faithful sample of the regSms HTML — three real codes
# (Telecommunications=1, Agriculture=3, Environment=13) plus a duplicate row to
# verify dedup. Spelling and entity encoding mirror the live page.
SAMPLE_REG_HTML_EN = """
<table>
  <tbody>
    <tr>
      <td>
        Telecommunications
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=1&srch=Search">120</a>
      </td>
    </tr>
    <tr>
      <td>
        Agriculture
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=3&srch=Search">798</a>
      </td>
    </tr>
    <tr>
      <td>
        Environment
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=13&srch=Search">1,540</a>
      </td>
    </tr>
    <!-- Trend column repeats the same Environment row — must dedup -->
    <tr>
      <td>
        Environment
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=13&srch=Search">1,510</a>
      </td>
    </tr>
  </tbody>
</table>
"""

SAMPLE_REG_HTML_FR = """
<table>
  <tbody>
    <tr>
      <td>
        Télécommunications
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=1&srch=Search">120</a>
      </td>
    </tr>
    <tr>
      <td>
        Agriculture
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=3&srch=Search">798</a>
      </td>
    </tr>
    <tr>
      <td>
        Vie privée et Accès à l&#039;information
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/advSrch?adv_2001_subjectMatter=43&srch=Search">87</a>
      </td>
    </tr>
  </tbody>
</table>
"""

SAMPLE_COMM_HTML = """
<table>
  <tbody>
    <!-- Selected-period table: code 45 = 1,828, code 3 = 501 in April 2026 -->
    <tr>
      <td>
        Economic Development
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/rcntSmCmLgs?cid=45&dt=2026-04">1,828</a>
      </td>
    </tr>
    <tr>
      <td>
        Agriculture
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/rcntSmCmLgs?cid=3&dt=2026-04">501</a>
      </td>
    </tr>
  </tbody>
</table>
<table>
  <tbody>
    <!-- Historical trend table: same April row (must dedup) + earlier months. -->
    <tr>
      <td>
        Economic Development
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/rcntSmCmLgs?dt=2026-04&cid=45&tb=historical">1,828</a>
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/rcntSmCmLgs?dt=2026-03&cid=45&tb=historical">1,500</a>
      </td>
    </tr>
    <tr>
      <td>
        Agriculture
      </td>
      <td class="text-right">
        <a href="/app/secure/ocl/lrs/do/rcntSmCmLgs?dt=2026-03&cid=3&tb=historical">408</a>
      </td>
    </tr>
  </tbody>
</table>
"""


class ParseSubjectLabelsTests(unittest.TestCase):
    def test_extracts_expected_row_count(self) -> None:
        labels = parse_subject_labels(SAMPLE_REG_HTML_EN)
        self.assertEqual(len(labels), 3)
        self.assertEqual(labels[1], "Telecommunications")
        self.assertEqual(labels[3], "Agriculture")
        self.assertEqual(labels[13], "Environment")

    def test_deduplicates_trend_columns(self) -> None:
        labels = parse_subject_labels(SAMPLE_REG_HTML_EN)
        # The Environment row appears twice in the sample (current + trend);
        # we should keep one entry, not two.
        self.assertEqual(sum(1 for code in labels if code == 13), 1)

    def test_unescapes_html_entities(self) -> None:
        labels = parse_subject_labels(SAMPLE_REG_HTML_FR)
        self.assertIn("Vie privée et Accès à l'information", labels.values())


class ParseCommunicationCountsTests(unittest.TestCase):
    def test_sums_across_periods_and_dedupes_overlapping_month(self) -> None:
        counts = parse_communication_counts(SAMPLE_COMM_HTML)
        # Code 45: April (1828) seen in both selected-period and historical
        # tables — counted once — plus March (1500) from historical = 3328.
        self.assertEqual(counts[45], 1828 + 1500)
        # Code 3: April (501) + March (408) = 909.
        self.assertEqual(counts[3], 501 + 408)

    def test_handles_comma_thousands_separator(self) -> None:
        counts = parse_communication_counts(SAMPLE_COMM_HTML)
        # 1,828 (April) + 1,500 (March) must both parse despite the commas.
        self.assertEqual(counts[45], 3328)

    def test_returns_empty_dict_when_no_links(self) -> None:
        self.assertEqual(parse_communication_counts("<html></html>"), {})


class MergeBilingualTests(unittest.TestCase):
    def test_joins_on_code(self) -> None:
        en = parse_subject_labels(SAMPLE_REG_HTML_EN)
        fr = parse_subject_labels(SAMPLE_REG_HTML_FR)
        subjects = merge_bilingual(en, fr)
        by_code = {s.ocl_code: s for s in subjects}
        self.assertEqual(by_code[1].label_en, "Telecommunications")
        self.assertEqual(by_code[1].label_fr, "Télécommunications")

    def test_keeps_code_present_in_only_one_language(self) -> None:
        # Code 13 appears only in EN sample; code 43 only in FR. Both should
        # surface so audits can spot the drift.
        en = parse_subject_labels(SAMPLE_REG_HTML_EN)
        fr = parse_subject_labels(SAMPLE_REG_HTML_FR)
        subjects = merge_bilingual(en, fr)
        codes = {s.ocl_code for s in subjects}
        self.assertIn(13, codes)
        self.assertIn(43, codes)
        thirteen = next(s for s in subjects if s.ocl_code == 13)
        self.assertEqual(thirteen.label_fr, "")

    def test_active_defaults_true(self) -> None:
        subjects = merge_bilingual(
            parse_subject_labels(SAMPLE_REG_HTML_EN),
            parse_subject_labels(SAMPLE_REG_HTML_FR),
        )
        self.assertTrue(all(s.active for s in subjects))


class MappingReportTests(unittest.TestCase):
    def _sample_subjects(self) -> list[OCLSubjectMatter]:
        return [
            OCLSubjectMatter(ocl_code=3, label_en="Agriculture", label_fr="Agriculture"),
            OCLSubjectMatter(ocl_code=45, label_en="Economic Development", label_fr="Développement économique"),
            OCLSubjectMatter(ocl_code=99, label_en="Hypothetical", label_fr="Hypothétique"),
        ]

    def test_unmapped_codes_surface_in_report(self) -> None:
        report = build_mapping_report(
            self._sample_subjects(),
            comm_counts={3: 501, 45: 1828, 99: 0},
            mapping={3: "agriculture"},
            as_of="2026-06-03",
        )
        self.assertIn("| 45 | Economic Development | 1,828 | unmapped | — |", report)
        self.assertIn("| 99 | Hypothetical | 0 | unmapped | — |", report)
        self.assertIn("Unmapped: **2**", report)

    def test_mapped_codes_show_topic(self) -> None:
        report = build_mapping_report(
            self._sample_subjects(),
            comm_counts={3: 501, 45: 1828, 99: 0},
            mapping={3: "agriculture"},
            as_of="2026-06-03",
        )
        self.assertIn("| 3 | Agriculture | 501 | mapped | agriculture |", report)
        self.assertIn("Mapped to EPAC topics: **1**", report)

    def test_orders_rows_by_communication_volume_desc(self) -> None:
        report = build_mapping_report(
            self._sample_subjects(),
            comm_counts={3: 501, 45: 1828, 99: 0},
            mapping={},
            as_of="2026-06-03",
        )
        # Economic Development (1828) must precede Agriculture (501)
        # which must precede Hypothetical (0).
        ed_index = report.index("Economic Development")
        agri_index = report.index("Agriculture")
        hypo_index = report.index("Hypothetical")
        self.assertLess(ed_index, agri_index)
        self.assertLess(agri_index, hypo_index)

    def test_empty_mapping_reports_every_code_unmapped(self) -> None:
        subjects = self._sample_subjects()
        report = build_mapping_report(
            subjects,
            comm_counts={},
            mapping={},
            as_of="2026-06-03",
        )
        self.assertEqual(report.count("| unmapped |"), len(subjects))


if __name__ == "__main__":
    unittest.main()
