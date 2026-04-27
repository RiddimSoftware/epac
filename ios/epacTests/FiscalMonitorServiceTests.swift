import Foundation
import Testing
@testable import epac

struct FiscalMonitorServiceTests {
	@Test func parsesFinanceCanadaFiscalMonitorHTML() throws {
		let html = """
		<html>
		<head><title>The Fiscal Monitor - February 2026</title></head>
		<body>
		<h1>The Fiscal Monitor - February 2026</h1>
		<p>Table 1</p>
		<p>Summary statement of transactions</p>
		<p>$ millions February April to February 2025 2026 2024-25 2025-26</p>
		<p>Budgetary transactions Revenues 51,247 48,415 449,834 453,246 Expenses Program expenses, excluding net actuarial losses -39,541 -38,449 -416,082 -424,924 Public debt charges -3,797 -3,892 -49,341 -49,306 Budgetary balance, excluding net actuarial losses 7,909 6,074 -15,589 -20,984 Net actuarial losses -335 -415 -3,685 -4,565 Budgetary balance (deficit/surplus) 7,574 5,659 -19,274 -25,549 Non-budgetary transactions</p>
		<p>Actual/projected annual budgetary balance 1 -36,348 -78,349 -32,328 -73,372 Table 1</p>
		<p>Page details 2026-04-24</p>
		</body>
		</html>
		"""

		let entry = try FiscalMonitorService.parseIssueHTML(
			html,
			sourceURL: URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2026/02.html")!
		)

		#expect(entry.id == "2026-02")
		#expect(entry.fiscalYear == "2025-26")
		#expect(entry.revenueMillions == 48_415)
		#expect(entry.expenseMillions == 42_756)
		#expect(entry.budgetaryBalanceMillions == 5_659)
		#expect(entry.yearToDateBalanceMillions == -25_549)
		#expect(entry.annualBudgetProjectionMillions == -78_349)
		#expect(entry.sourceTitle == "Finance Canada Fiscal Monitor, February 2026")
	}
}
