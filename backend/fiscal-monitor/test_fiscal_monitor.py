import unittest

from fiscal_monitor import parse_issue_html


class FiscalMonitorParserTests(unittest.TestCase):
    def test_parse_issue_html(self):
        html = """
        <html><body>
        <h1>The Fiscal Monitor - February 2026</h1>
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


if __name__ == "__main__":
    unittest.main()
