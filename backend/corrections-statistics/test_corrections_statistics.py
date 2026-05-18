import hashlib
import json
import unittest

import corrections_statistics


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


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

    def test_publish_payload_writes_s3_artifact_with_content_hash(self):
        payload = corrections_statistics.build_statistics()
        s3_client = FakeS3Client()

        published = corrections_statistics.publish_payload(
            payload,
            bucket="artifact-bucket",
            s3_client=s3_client,
        )

        self.assertEqual(published[0].key, "statistics/v1/corrections-statistics/all.json")
        call = s3_client.calls[0]
        self.assertEqual(call["Bucket"], "artifact-bucket")
        self.assertEqual(call["Key"], "statistics/v1/corrections-statistics/all.json")
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
