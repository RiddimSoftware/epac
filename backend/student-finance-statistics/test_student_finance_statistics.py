import hashlib
import io
import json
import unittest
from zipfile import ZipFile

import student_finance_statistics as stats


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


class StudentFinanceStatisticsTests(unittest.TestCase):
    def test_parse_table_zip(self):
        data = io.BytesIO()
        with ZipFile(data, "w") as archive:
            archive.writestr(
                "37100120.csv",
                "REF_DATE,GEO,Field of study,UOM,VALUE\n2025/2026,Ontario,\"Total, field of study\",Current dollars,8958\n",
            )

        rows = stats.parse_table_zip(data.getvalue(), "37100120.csv")

        self.assertEqual(rows[0]["GEO"], "Ontario")
        self.assertEqual(rows[0]["VALUE"], "8958")

    def test_build_statistics_composes_tuition_and_csfa(self):
        rows = [
            {"REF_DATE": "2024/2025", "GEO": "Ontario", "Field of study": "Total, field of study", "UOM": "Current dollars", "VALUE": "8814"},
            {"REF_DATE": "2025/2026", "GEO": "Ontario", "Field of study": "Total, field of study", "UOM": "Current dollars", "VALUE": "8958"},
            {"REF_DATE": "2025/2026", "GEO": "Canada", "Field of study": "Total, field of study", "UOM": "Current dollars", "VALUE": "7734"},
            {"REF_DATE": "2025/2026", "GEO": "Ontario", "Field of study": "Education", "UOM": "Current dollars", "VALUE": "7000"},
        ]

        snapshot = stats.build_statistics(rows, tuition_year_count=2)
        ontario = next(item for item in snapshot["provinces"] if item["province_code"] == "ON")

        self.assertTrue(ontario["csfa_participating"])
        self.assertEqual(ontario["tuition_years"][-1]["average_undergraduate_tuition"], 8958)
        self.assertEqual(ontario["tuition_years"][-1]["year_over_year_change_percent"], 1.6)
        self.assertEqual(ontario["csfa_years"][-1]["loan_recipients"], 377860)
        self.assertEqual(ontario["csfa_years"][-1]["rap_recipients"], 160576)

    def test_publish_payload_writes_s3_artifacts_with_content_hash(self):
        rows = [
            {
                "REF_DATE": "2025/2026",
                "GEO": "Ontario",
                "Field of study": "Total, field of study",
                "UOM": "Current dollars",
                "VALUE": "8958",
            }
        ]
        payload = stats.build_statistics(rows, tuition_year_count=1)
        s3_client = FakeS3Client()

        published = stats.publish_payload(payload, bucket="artifact-bucket", s3_client=s3_client)

        keys = [call["Key"] for call in s3_client.calls]
        self.assertEqual(published[0].key, "statistics/v1/student-finance-statistics/all.json")
        self.assertIn("statistics/v1/student-finance-statistics/province-on.json", keys)
        call = s3_client.calls[0]
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
