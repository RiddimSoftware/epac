import hashlib
import json
import unittest

import ei_statistics
from ei_statistics import build_statistics


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


def beneficiary_row(month, province, value):
    return {
        "REF_DATE": month,
        "GEO": province,
        "Beneficiary detail": "Regular benefits",
        "Sex": "Both sexes",
        "Age group": "15 years and over",
        "VALUE": str(value),
    }


def claim_row(month, province, value):
    return {
        "REF_DATE": month,
        "GEO": province,
        "Type of claim": "Initial and renewal claims",
        "Claim detail": "Received",
        "VALUE": str(value),
    }


def benefit_row(month, province, characteristic, value):
    return {
        "REF_DATE": month,
        "GEO": province,
        "Benefit characteristics": characteristic,
        "VALUE": str(value),
    }


class EIStatisticsTests(unittest.TestCase):
    def test_build_statistics_composes_latest_snapshot(self):
        beneficiary_rows = [
            beneficiary_row("2025-03", "Ontario", 100),
            beneficiary_row("2026-01", "Ontario", 120),
            beneficiary_row("2026-02", "Ontario", 130),
            beneficiary_row("2026-03", "Ontario", 140),
            beneficiary_row("2026-03", "Canada", 999),
        ]
        claim_rows = [
            claim_row("2025-03", "Ontario", 80),
            claim_row("2026-01", "Ontario", 82),
            claim_row("2026-02", "Ontario", 84),
            claim_row("2026-03", "Ontario", 100),
        ]
        benefit_rows = [
            benefit_row("2025-03", "Ontario", "Benefit payments", 40_000),
            benefit_row("2025-03", "Ontario", "Benefit weeks", 100),
            benefit_row("2026-01", "Ontario", "Benefit payments", 49_200),
            benefit_row("2026-01", "Ontario", "Benefit weeks", 120),
            benefit_row("2026-02", "Ontario", "Benefit payments", 53_300),
            benefit_row("2026-02", "Ontario", "Benefit weeks", 130),
            benefit_row("2026-03", "Ontario", "Benefit payments", 58_800),
            benefit_row("2026-03", "Ontario", "Benefit weeks", 140),
        ]

        payload = build_statistics(beneficiary_rows, claim_rows, benefit_rows, months=2)

        self.assertEqual(payload["reference_month"], "2026-03")
        self.assertEqual(len(payload["provinces"]), 1)
        ontario = payload["provinces"][0]
        self.assertEqual(ontario["province_code"], "ON")
        self.assertEqual(ontario["beneficiaries"], 140)
        self.assertEqual(ontario["claims_received_previous_year"], 80)
        self.assertEqual(ontario["claims_year_over_year_change_percent"], 25.0)
        self.assertEqual(ontario["average_weekly_benefit"], 420.0)
        self.assertEqual([month["ref_date"] for month in ontario["months"]], ["2026-02", "2026-03"])

    def test_missing_previous_year_claims_returns_null_change(self):
        beneficiary_rows = [beneficiary_row("2026-03", "Alberta", 50)]
        claim_rows = [claim_row("2026-03", "Alberta", 20)]
        benefit_rows = [
            benefit_row("2026-03", "Alberta", "Benefit payments", 10_000),
            benefit_row("2026-03", "Alberta", "Benefit weeks", 20),
        ]

        payload = build_statistics(beneficiary_rows, claim_rows, benefit_rows)

        alberta = payload["provinces"][0]
        self.assertIsNone(alberta["claims_received_previous_year"])
        self.assertIsNone(alberta["claims_year_over_year_change_percent"])

    def test_publish_payload_writes_s3_artifacts_with_content_hash(self):
        beneficiary_rows = [beneficiary_row("2026-03", "Ontario", 140)]
        claim_rows = [claim_row("2026-03", "Ontario", 100)]
        benefit_rows = [
            benefit_row("2026-03", "Ontario", "Benefit payments", 58_800),
            benefit_row("2026-03", "Ontario", "Benefit weeks", 140),
        ]
        payload = build_statistics(beneficiary_rows, claim_rows, benefit_rows)
        s3_client = FakeS3Client()

        published = ei_statistics.publish_payload(payload, bucket="artifact-bucket", s3_client=s3_client)

        keys = [call["Key"] for call in s3_client.calls]
        self.assertEqual(published[0].key, "statistics/v1/ei-statistics/all.json")
        self.assertIn("statistics/v1/ei-statistics/province-on.json", keys)
        call = s3_client.calls[0]
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
