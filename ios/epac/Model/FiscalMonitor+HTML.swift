import Foundation
import Kanna

extension FiscalMonitorEntry {
	static let defaultAnnualBudgetProjectionMillions = -78300.0

	static func fromHTML(_ html: String, sourceURL: URL) throws -> [FiscalMonitorEntry] {
		guard let doc = try? HTML(html: html, url: nil, encoding: .utf8) else {
			throw NSError(domain: "FiscalMonitorEntry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Fiscal Monitor HTML"])
		}

		guard let title = doc.at_css("h1")?.text?.normalizedWhitespace,
			  let publicationDate = Self.publicationDate(from: doc) else {
			throw NSError(domain: "FiscalMonitorEntry", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fiscal Monitor title or publication date missing"])
		}

		let year = Calendar.current.component(.year, from: publicationDate)
		let table = doc.css("table").first { table in
			table.at_css("caption")?.text?.normalizedWhitespace.contains("Summary statement of transactions") == true
		}

		guard let table else {
			throw NSError(domain: "FiscalMonitorEntry", code: 3, userInfo: [NSLocalizedDescriptionKey: "Summary statement table missing"])
		}

		let rows = table.css("tr").map { row in
			row.css("th, td").map { $0.text?.normalizedWhitespace ?? "" }
		}

		let revenue = Self.values(for: "Revenues", in: rows)
		let spending = Self.values(for: "Total expenses", in: rows)
		let balance = Self.values(for: "Budgetary balance (deficit/surplus)", in: rows)

		if title.contains("April and May") {
			guard revenue.count >= 6, spending.count >= 6, balance.count >= 6 else {
				throw NSError(domain: "FiscalMonitorEntry", code: 4, userInfo: [NSLocalizedDescriptionKey: "April/May Fiscal Monitor table has unexpected columns"])
			}
			return [
				FiscalMonitorEntry(
					fiscalYearStartYear: year,
					month: 4,
					monthName: "April",
					publicationDate: publicationDate,
					revenueMillions: revenue[1],
					spendingMillions: spending[1],
					balanceMillions: balance[1],
					yearToDateRevenueMillions: revenue[1],
					yearToDateSpendingMillions: spending[1],
					yearToDateBalanceMillions: balance[1],
					budgetProjectionMillions: defaultAnnualBudgetProjectionMillions,
					sourceURL: sourceURL
				),
				FiscalMonitorEntry(
					fiscalYearStartYear: year,
					month: 5,
					monthName: "May",
					publicationDate: publicationDate,
					revenueMillions: revenue[3],
					spendingMillions: spending[3],
					balanceMillions: balance[3],
					yearToDateRevenueMillions: revenue[5],
					yearToDateSpendingMillions: spending[5],
					yearToDateBalanceMillions: balance[5],
					budgetProjectionMillions: defaultAnnualBudgetProjectionMillions,
					sourceURL: sourceURL
				)
			]
		}

		guard let month = Self.monthAndNumber(from: title), revenue.count >= 4, spending.count >= 4, balance.count >= 4 else {
			throw NSError(domain: "FiscalMonitorEntry", code: 5, userInfo: [NSLocalizedDescriptionKey: "Fiscal Monitor table has unexpected columns"])
		}

		let fiscalYearStartYear = month.number >= 4 ? year : year - 1
		return [
			FiscalMonitorEntry(
				fiscalYearStartYear: fiscalYearStartYear,
				month: month.number,
				monthName: month.name,
				publicationDate: publicationDate,
				revenueMillions: revenue[1],
				spendingMillions: spending[1],
				balanceMillions: balance[1],
				yearToDateRevenueMillions: revenue[3],
				yearToDateSpendingMillions: spending[3],
				yearToDateBalanceMillions: balance[3],
				budgetProjectionMillions: defaultAnnualBudgetProjectionMillions,
				sourceURL: sourceURL
			)
		]
	}

	private static func values(for rowTitle: String, in rows: [[String]]) -> [Double] {
		rows.first { row in
			row.first?.caseInsensitiveCompare(rowTitle) == .orderedSame
		}?
		.dropFirst()
		.compactMap(Self.number)
		?? []
	}

	private static func publicationDate(from doc: HTMLDocument) -> Date? {
		let value = doc.at_css("meta[name='dcterms.issued']")?["content"]
			?? doc.at_css("meta[name='dcterms.modified']")?["content"]
		guard let value else { return nil }
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_CA_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.date(from: value)
	}

	private static func monthAndNumber(from title: String) -> (name: String, number: Int)? {
		let months = DateFormatter().monthSymbols ?? []
		for (index, month) in months.enumerated() where title.contains(month) {
			return (month, index + 1)
		}
		return nil
	}

	private static func number(from text: String) -> Double? {
		let cleaned = text
			.replacingOccurrences(of: ",", with: "")
			.replacingOccurrences(of: "$", with: "")
			.replacingOccurrences(of: "\u{00a0}", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return Double(cleaned)
	}
}

private extension String {
	var normalizedWhitespace: String {
		components(separatedBy: .whitespacesAndNewlines)
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}
}
