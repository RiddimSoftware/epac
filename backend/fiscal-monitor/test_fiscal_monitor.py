from dataclasses import asdict
import hashlib
import json
import unittest

import fiscal_monitor
from fiscal_monitor import parse_issue_html


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


class FiscalMonitorParserTests(unittest.TestCase):
    def test_parse_issue_html(self):
        html = """
        <html><body>
        <h1>The Fiscal Monitor - February 2026</h1>
        <a class="gc-dwnld-lnk" href="/content/dam/fin/publications/fm-rf/2026/02/2026-02-eng.pdf">PDF</a>
        <p>Table 1 Summary statement of transactions</p>
        <p>Budgetary transactions Revenues 51,247 48,415 449,834 453,246 Expenses Program expenses, excluding net actuarial losses -39,541 -38,449 -416,082 -424,924 Public debt charges -3,797 -3,892 -49,341 -49,306 Budgetary balance, excluding net actuarial losses 7,909 6,074 -15,589 -20,984 Net actuarial losses -335 -415 -3,685 -4,565 Budgetary balance (deficit/surplus) 7,574 5,659 -19,274 -25,549 Non-budgetary transactions</p>
        <p>Actual/projected annual budgetary balance 1 -36,348 -78,349 -32,328 -73,372 Table 1</p>
        <p>Page details 2026-04-24</p>
        </body></html>
        """

        entry = parse_issue_html(
            html,
            "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2026/02.html",
        )

        self.assertEqual(entry.id, "2026-02")
        self.assertEqual(entry.fiscal_year, "2025-26")
        self.assertEqual(entry.publication_date, "2026-04-24")
        self.assertEqual(entry.revenue_millions, 48415)
        self.assertEqual(entry.expense_millions, 42756)
        self.assertEqual(entry.budgetary_balance_millions, 5659)
        self.assertEqual(entry.year_to_date_balance_millions, -25549)
        self.assertEqual(entry.annual_budget_projection_millions, -78349)
        self.assertEqual(
            entry.source_url,
            "https://www.canada.ca/content/dam/fin/publications/fm-rf/2026/02/2026-02-eng.pdf",
        )

    def test_publish_payload_writes_s3_artifact_with_content_hash(self):
        entry = parse_issue_html(
            """
            <html><body>
            <h1>The Fiscal Monitor - February 2026</h1>
            <p>Table 1 Summary statement of transactions</p>
            <p>Budgetary transactions Revenues 51,247 48,415 449,834 453,246 Expenses Program expenses, excluding net actuarial losses -39,541 -38,449 -416,082 -424,924 Public debt charges -3,797 -3,892 -49,341 -49,306 Budgetary balance (deficit/surplus) 7,574 5,659 -19,274 -25,549 Non-budgetary transactions</p>
            <p>Actual/projected annual budgetary balance 1 -36,348 -78,349 -32,328 -73,372 Table 1</p>
            <p>Page details 2026-04-24</p>
            </body></html>
            """,
            "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2026/02.html",
        )
        payload = [asdict(entry)]
        s3_client = FakeS3Client()

        published = fiscal_monitor.publish_payload(payload, bucket="artifact-bucket", s3_client=s3_client)

        self.assertEqual(published[0].key, "statistics/v1/fiscal-monitor/all.json")
        call = s3_client.calls[0]
        self.assertEqual(call["Bucket"], "artifact-bucket")
        self.assertEqual(call["Key"], "statistics/v1/fiscal-monitor/all.json")
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
