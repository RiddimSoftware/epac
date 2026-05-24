import hashlib
import json
import unittest

import cpi_statistics
from cpi_statistics import build_statistics


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


def cpi_row(month, geography, category, value):
    return {
        "REF_DATE": month,
        "GEO": geography,
        "Products and product groups": category,
        "VALUE": str(value),
    }


def category_rows(month, geography, all_items, food, shelter, energy):
    return [
        cpi_row(month, geography, "All-items", all_items),
        cpi_row(month, geography, "Food", food),
        cpi_row(month, geography, "Shelter", shelter),
        cpi_row(month, geography, "Energy", energy),
    ]


class CPIStatisticsTests(unittest.TestCase):
    def test_build_statistics_composes_latest_snapshot(self):
        rows = []
        rows.extend(category_rows("2025-03", "Canada", 150.0, 180.0, 170.0, 210.0))
        rows.extend(category_rows("2026-02", "Canada", 151.0, 183.0, 172.0, 213.0))
        rows.extend(category_rows("2026-03", "Canada", 153.0, 187.2, 176.8, 207.9))
        rows.extend(category_rows("2025-03", "Ontario", 160.0, 190.0, 180.0, 200.0))
        rows.extend(category_rows("2026-02", "Ontario", 162.0, 194.0, 181.0, 203.0))
        rows.extend(category_rows("2026-03", "Ontario", 164.0, 199.5, 183.6, 208.0))
        rows.extend(category_rows("2026-03", "Toronto, Ontario", 999.0, 999.0, 999.0, 999.0))

        payload = build_statistics(rows, months=2)

        self.assertEqual(payload["reference_month"], "2026-03")
        self.assertEqual(payload["national"]["all_items_yoy_percent"], 2.0)
        self.assertEqual(len(payload["provinces"]), 1)
        ontario = payload["provinces"][0]
        self.assertEqual(ontario["province_code"], "ON")
        self.assertEqual(ontario["all_items_index"], 164.0)
        self.assertEqual(ontario["all_items_yoy_percent"], 2.5)
        self.assertEqual(ontario["food_yoy_percent"], 5.0)
        self.assertEqual(ontario["shelter_yoy_percent"], 2.0)
        self.assertEqual(ontario["energy_yoy_percent"], 4.0)
        self.assertEqual(ontario["national_all_items_yoy_percent"], 2.0)
        self.assertEqual([month["ref_date"] for month in ontario["months"]], ["2026-03"])

    def test_missing_previous_year_values_are_skipped(self):
        rows = []
        rows.extend(category_rows("2025-03", "Canada", 150.0, 180.0, 170.0, 210.0))
        rows.extend(category_rows("2026-03", "Canada", 153.0, 187.2, 176.8, 207.9))
        rows.extend(category_rows("2026-03", "Alberta", 140.0, 170.0, 160.0, 220.0))

        with self.assertRaises(ValueError):
            build_statistics(rows)

    def test_publish_payload_writes_s3_artifacts_with_content_hash(self):
        rows = []
        rows.extend(category_rows("2025-03", "Canada", 150.0, 180.0, 170.0, 210.0))
        rows.extend(category_rows("2026-03", "Canada", 153.0, 187.2, 176.8, 207.9))
        rows.extend(category_rows("2025-03", "Ontario", 160.0, 190.0, 180.0, 200.0))
        rows.extend(category_rows("2026-03", "Ontario", 164.0, 199.5, 183.6, 208.0))
        payload = build_statistics(rows)
        s3_client = FakeS3Client()

        published = cpi_statistics.publish_payload(payload, bucket="artifact-bucket", s3_client=s3_client)

        keys = [call["Key"] for call in s3_client.calls]
        self.assertEqual(published[0].key, "statistics/v1/cpi-statistics/all.json")
        self.assertIn("statistics/v1/cpi-statistics/national.json", keys)
        self.assertIn("statistics/v1/cpi-statistics/province-on.json", keys)
        all_call = s3_client.calls[0]
        self.assertEqual(all_call["Bucket"], "artifact-bucket")
        self.assertEqual(json.loads(all_call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            all_call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(all_call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
