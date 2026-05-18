import hashlib
import json
import unittest

import vac_statistics


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


class VACStatisticsTests(unittest.TestCase):
    def test_build_payload_contains_vac_snapshot(self):
        payload = vac_statistics.build_payload()

        self.assertEqual(payload["national_summary"]["disability_benefit_recipients"], 144174)
        self.assertEqual(payload["national_summary"]["backlog_applications"], 5637)
        self.assertEqual(payload["annual"][-1]["fiscal_year"], "2024-25")
        self.assertEqual(payload["annual"][-1]["disability_pension_recipients"], 67100)
        self.assertEqual(payload["annual"][-1]["pain_and_suffering_compensation_recipients"], 119400)
        self.assertEqual(payload["annual"][-1]["additional_pain_and_suffering_compensation_recipients"], 33000)
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

    def test_publish_payload_writes_s3_artifacts_with_content_hash(self):
        payload = vac_statistics.build_payload()
        s3_client = FakeS3Client()

        published = vac_statistics.publish_payload(payload, bucket="artifact-bucket", s3_client=s3_client)

        keys = [call["Key"] for call in s3_client.calls]
        self.assertEqual(published[0].key, "statistics/v1/vac-statistics/all.json")
        self.assertIn("statistics/v1/vac-statistics/national.json", keys)
        self.assertIn("statistics/v1/vac-statistics/province-on.json", keys)
        call = s3_client.calls[0]
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
