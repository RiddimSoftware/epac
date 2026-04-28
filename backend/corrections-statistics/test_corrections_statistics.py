import unittest

import corrections_statistics


class CorrectionsStatisticsTests(unittest.TestCase):
    def test_build_statistics_contains_latest_three_years(self):
        snapshot = corrections_statistics.build_statistics()
        annual = snapshot["annual_statistics"]

        self.assertEqual("2023 to 2024", snapshot["reference_fiscal_year"])
        self.assertEqual(3, len(annual))
        self.assertEqual("2021 to 2022", annual[0]["fiscal_year"])
        self.assertEqual("2023 to 2024", annual[-1]["fiscal_year"])
        self.assertEqual(13855, annual[-1]["total_in_custody"])
        self.assertEqual(4579, annual[-1]["indigenous_in_custody"])
        self.assertEqual(33.0, annual[-1]["indigenous_in_custody_percent"])
        self.assertEqual(10.1, annual[-1]["recidivism_rate_percent"])
        self.assertEqual(152956, annual[-1]["cost_per_inmate"])

    def test_source_metadata_distinguishes_csc_oci_and_statcan(self):
        snapshot = corrections_statistics.build_statistics()
        titles = [source["title"] for source in snapshot["sources"]]

        self.assertTrue(any("Departmental Results Report" in title for title in titles))
        self.assertTrue(any("Office of the Correctional Investigator" in title for title in titles))
        self.assertTrue(any("Statistics Canada" in title for title in titles))
        self.assertEqual(5.0, snapshot["indigenous_population_share"]["percent_of_canada"])
        self.assertGreaterEqual(len(snapshot["oci_highlights"]), 3)


if __name__ == "__main__":
    unittest.main()
