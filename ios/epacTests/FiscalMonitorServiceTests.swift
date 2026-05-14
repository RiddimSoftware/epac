@testable import epac
import Foundation
import Testing

struct FiscalMonitorServiceTests {
	@Test func parseFiscalMonitorIssue() throws {
		let html = """
		<html>
		<head>
			<title>The Fiscal Monitor - December 2025 - Canada.ca</title>
			<meta name="dcterms.issued" content="2026-02-27"/>
		</head>
		<body>
			<a class="gc-dwnld-lnk" href="/content/dam/fin/publications/fm-rf/2025/12/2025-12-eng.pdf">Download PDF</a>
			<table class="table table-bordered">
				<caption>Table 1<br><strong>Summary statement of transactions</strong><br><small>$ millions</small></caption>
				<tbody>
					<tr><th scope="row" class="fnt-nrml">Revenues</th><td>44,335</td><td>46,116</td><td>355,624</td><td>363,361</td></tr>
					<tr><th scope="row" class="fnt-nrml">Program expenses, excluding net actuarial losses</th><td>-38,277</td><td>-40,906</td><td>-333,201</td><td>-344,910</td></tr>
					<tr><th scope="row" class="fnt-nrml">Public debt charges</th><td>-4,721</td><td>-4,550</td><td>-41,123</td><td>-40,856</td></tr>
					<tr><th scope="row" class="fnt-nrml">Net actuarial losses</th><td>-335</td><td>-415</td><td>-3,015</td><td>-3,735</td></tr>
					<tr><th scope="row">Budgetary balance (deficit/surplus)</th><td>1,002</td><td>245</td><td>-21,715</td><td>-26,140</td></tr>
				</tbody>
			</table>
			<table>
				<tbody>
					<tr><th>Actual/projected annual budgetary balance</th><td>-36,348</td><td>-78,349</td></tr>
				</tbody>
			</table>
		</body>
		</html>
		"""

		let url = URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2025/12.html")!
		let entry = try FiscalMonitorService.parseIssue(html: html, url: url)

		#expect(entry.fiscalYearStart == 2025)
		#expect(entry.month == 12)
		#expect(entry.monthName == "December")
		#expect(entry.revenueMillions == 46_116)
		#expect(entry.programExpenseMillions == 40_906)
		#expect(entry.publicDebtChargesMillions == 4_550)
		#expect(entry.netActuarialLossesMillions == 415)
		#expect(entry.budgetaryBalanceMillions == 245)
		#expect(entry.yearToDateBudgetaryBalanceMillions == -26_140)
		#expect(entry.annualBudgetProjectionMillions == -78_349)
		#expect(entry.sourceTitle == "Finance Canada Fiscal Monitor, December 2025")
		#expect(entry.sourceURL == "https://www.canada.ca/content/dam/fin/publications/fm-rf/2025/12/2025-12-eng.pdf")
	}

	@Test func parseIssueAcceptsFootnotedRevenueRow() throws {
		let html = fiscalMonitorHTML(
			rows: """
					<tr><th scope="row" class="fnt-nrml">Revenues<sup>1</sup></th><td>31,949</td><td>33,657</td><td>83,389</td><td>89,855</td></tr>
					<tr><th scope="row" class="fnt-nrml">Program expenses, excluding net actuarial losses</th><td>-42,190</td><td>-40,000</td><td>-86,290</td><td>-87,000</td></tr>
					<tr><th scope="row" class="fnt-nrml">Public debt charges</th><td>-4,386</td><td>-4,513</td><td>-8,556</td><td>-8,886</td></tr>
					<tr><th scope="row" class="fnt-nrml">Net actuarial losses</th><td>-335</td><td>-415</td><td>-670</td><td>-830</td></tr>
					<tr><th scope="row">Budgetary balance (deficit/surplus)</th><td>-14,962</td><td>-11,271</td><td>-12,127</td><td>-6,861</td></tr>
			"""
		)

		let url = URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2025/06.html")!
		let entry = try FiscalMonitorService.parseIssue(html: html, url: url)

		#expect(entry.revenueMillions == 33_657)
		#expect(entry.yearToDateBudgetaryBalanceMillions == -6_861)
	}

	@Test func parseIssueAcceptsNetActuarialLossesAndGainsLabels() throws {
		let html = fiscalMonitorHTML(
			rows: """
					<tr><th scope="row" class="fnt-nrml">Revenues</th><td>40,000</td><td>41,000</td><td>200,000</td><td>205,000</td></tr>
					<tr><th scope="row" class="fnt-nrml">Program expenses, excluding net actuarial losses and gains</th><td>-38,000</td><td>-39,000</td><td>-190,000</td><td>-191,000</td></tr>
					<tr><th scope="row" class="fnt-nrml">Public debt charges</th><td>-4,000</td><td>-4,200</td><td>-20,000</td><td>-20,500</td></tr>
					<tr><th scope="row" class="fnt-nrml">Net actuarial (losses) gains</th><td>126</td><td>-466</td><td>-1,553</td><td>-2,535</td></tr>
					<tr><th scope="row">Budgetary balance (deficit/surplus)</th><td>-1,874</td><td>-2,666</td><td>-11,553</td><td>-9,035</td></tr>
			"""
		)

		let url = URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2025/09.html")!
		let entry = try FiscalMonitorService.parseIssue(html: html, url: url)

		#expect(entry.programExpenseMillions == 39_000)
		#expect(entry.netActuarialLossesMillions == 466)
		#expect(entry.budgetaryBalanceMillions == -2_666)
	}

	@Test func parseIssueLinksFindsCurrentFiscalYearCandidates() throws {
		let html = """
		<html><body>
			<a href="/en/department-finance/services/publications/fiscal-monitor/2025/03.html">March</a>
			<a href="/en/department-finance/services/publications/fiscal-monitor/2025/04.html">April</a>
			<a href="/en/department-finance/services/publications/fiscal-monitor/2025/12.html">December</a>
			<a href="/en/department-finance/services/publications/fiscal-monitor/2026/01.html">January</a>
		</body></html>
		"""

		let issues = try FiscalMonitorService.parseIssueLinks(
			html: html,
			baseURL: URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor.html")!
		)

		#expect(issues.count == 4)
		#expect(issues.contains { $0.year == 2025 && $0.month == 4 && $0.fiscalYearStart == 2025 })
		#expect(issues.contains { $0.year == 2026 && $0.month == 1 && $0.fiscalYearStart == 2025 })
	}

	@Test func parsePublicationJSONFindsFiscalMonitorIssues() throws {
		let json = """
		{
			"data": [
				{
					"title": "The Fiscal Monitor - February 2026",
					"link": "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2026/02.html",
					"pub-type": "Fiscal Monitor"
				},
				{
					"title": "Official International Reserves - April 7, 2026",
					"link": "https://www.canada.ca/en/department-finance/services/publications/monthly-official-international-reserves/2026/04.html",
					"pub-type": "Official International Reserves"
				},
				{
					"title": "The Fiscal Monitor - April 2025",
					"link": "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor/2025/04.html",
					"pub-type": "Fiscal Monitor"
				}
			]
		}
		"""

		let issues = try FiscalMonitorService.parsePublicationIssues(
			json: Data(json.utf8),
			baseURL: URL(string: "https://www.canada.ca/content/dam/fin/documents/publications/pub-rep/json.json")!
		)

		#expect(issues.count == 2)
		#expect(issues.contains { $0.year == 2026 && $0.month == 2 && $0.fiscalYearStart == 2025 })
		#expect(issues.contains { $0.year == 2025 && $0.month == 4 && $0.fiscalYearStart == 2025 })
	}

	private func fiscalMonitorHTML(rows: String) -> String {
		"""
		<html>
		<head>
			<title>The Fiscal Monitor</title>
			<meta name="dcterms.issued" content="2026-02-27"/>
		</head>
		<body>
			<table class="table table-bordered">
				<caption>Table 1<br><strong>Summary statement of transactions</strong><br><small>$ millions</small></caption>
				<tbody>
		\(rows)
				</tbody>
			</table>
		</body>
		</html>
		"""
	}
}
