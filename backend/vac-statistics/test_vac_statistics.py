import json
import unittest

import vac_statistics


class VACStatisticsTests(unittest.TestCase):
    def test_build_payload_contains_vac_snapshot(self):
        payload = vac_statistics.build_payload()

        self.assertEqual(payload["national_summary"]["disability_benefit_recipients"], 144174)
        self.assertEqual(payload["national_summary"]["backlog_applications"], 5637)
        self.assertEqual(payload["annual"][-1]["fiscal_year"], "2024-25")
        self.assertEqual(payload["annual"][-1]["benefits_services_support_spending_dollars"], 7425077871)
        self.assertEqual(len(payload["provinces"]), 10)
        ontario = next(item for item in payload["provinces"] if item["province_code"] == "ON")
        self.assertEqual(ontario["census_veterans"], 149020)

    def test_main_writes_output(self):
        with self.subTest("writes JSON to a temporary file"):
            import tempfile

            with tempfile.TemporaryDirectory() as directory:
                output = f"{directory}/vac-statistics.json"
                self.assertEqual(vac_statistics.main(["--output", output]), 0)

                with open(output, encoding="utf-8") as handle:
                    payload = json.load(handle)
                self.assertTrue(payload["source"]["title"].startswith("Veterans Affairs Canada"))


if __name__ == "__main__":
    unittest.main()
