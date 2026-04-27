import Foundation
import Testing
@testable import epac

struct FiscalMonitorTests {
	@Test func parsesStandardMonthlyFiscalMonitorTable() throws {
		let html = """
<html>
<head><meta name="dcterms.issued" content="2026-04-24"></head>
<body>
<h1>The Fiscal Monitor - February 2026</h1>
<table>
<caption>Table 1<br><strong>Summary statement of transactions</strong><br><small>$ millions</small></caption>
<tbody>
<tr><th>Revenues</th><td>51,247</td><td>48,415</td><td>449,845</td><td>453,224</td></tr>
<tr><th>Expenses</th></tr>
<tr><th>Total expenses</th><td>43,673</td><td>42,756</td><td>469,172</td><td>478,757</td></tr>
<tr><th>Budgetary balance (deficit/surplus)</th><td>7,574</td><td>5,659</td><td>-19,327</td><td>-25,533</td></tr>
</tbody>
</table>
</body>
</html>
"""
		let entries = try FiscalMonitorEntry.fromHTML(html, sourceURL: URL(string: "https://example.com/2026/02.html")!)

		#expect(entries.count == 1)
		#expect(entries[0].fiscalYearStartYear == 2025)
		#expect(entries[0].month == 2)
		#expect(entries[0].monthName == "February")
		#expect(entries[0].revenueMillions == 48415)
		#expect(entries[0].spendingMillions == 42756)
		#expect(entries[0].balanceMillions == 5659)
		#expect(entries[0].yearToDateRevenueMillions == 453224)
		#expect(entries[0].yearToDateSpendingMillions == 478757)
		#expect(entries[0].yearToDateBalanceMillions == -25533)
	}

	@Test func parsesAprilMayCombinedFiscalMonitorTableAsTwoEntries() throws {
		let html = """
<html>
<head><meta name="dcterms.issued" content="2025-07-31"></head>
<body>
<h1>The Fiscal Monitor - April and May 2025</h1>
<table>
<caption>Table 1<br><strong>Summary statement of transactions</strong><br><small>$ millions</small></caption>
<tbody>
<tr><th>Revenues</th><td>41,008</td><td>40,329</td><td>38,594</td><td>39,270</td><td>79,602</td><td>79,599</td><td>-3</td></tr>
<tr><th>Expenses</th></tr>
<tr><th>Total expenses</th><td>46,002</td><td>46,600</td><td>37,422</td><td>39,498</td><td>83,424</td><td>86,098</td><td>2,674</td></tr>
<tr><th>Budgetary balance (deficit/surplus)</th><td>-4,994</td><td>-6,271</td><td>1,172</td><td>-228</td><td>-3,822</td><td>-6,499</td><td>-2,677</td></tr>
</tbody>
</table>
</body>
</html>
"""
		let entries = try FiscalMonitorEntry.fromHTML(html, sourceURL: URL(string: "https://example.com/2025/04.html")!)

		#expect(entries.count == 2)
		#expect(entries[0].month == 4)
		#expect(entries[0].balanceMillions == -6271)
		#expect(entries[0].yearToDateBalanceMillions == -6271)
		#expect(entries[1].month == 5)
		#expect(entries[1].balanceMillions == -228)
		#expect(entries[1].yearToDateBalanceMillions == -6499)
	}
}
