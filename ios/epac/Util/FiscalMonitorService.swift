//
//  FiscalMonitorService.swift
//  epac
//

import Foundation
import Kanna

struct FiscalMonitorIssue: Sendable, Hashable {
	let year: Int
	let month: Int
	let url: URL

	var fiscalYearStart: Int {
		month >= 4 ? year : year - 1
	}
}

struct FiscalMonitorParsedEntry: Sendable {
	let fiscalYearStart: Int
	let month: Int
	let monthName: String
	let periodDate: Date
	let publicationDate: Date
	let revenueMillions: Double
	let programExpenseMillions: Double
	let publicDebtChargesMillions: Double
	let netActuarialLossesMillions: Double
	let budgetaryBalanceMillions: Double
	let yearToDateBudgetaryBalanceMillions: Double
	let annualBudgetProjectionMillions: Double?
	let sourceTitle: String
	let sourceURL: String
}

enum FiscalMonitorServiceError: LocalizedError {
	case invalidHTML
	case noIssueLinks
	case summaryTableMissing(URL)
	case valueMissing(String, URL)
	case invalidPeriod(URL)

	var errorDescription: String? {
		switch self {
		case .invalidHTML:
			return "Could not parse Fiscal Monitor HTML."
		case .noIssueLinks:
			return "No Fiscal Monitor issue links were found."
		case .summaryTableMissing(let url):
			return "Summary statement table missing from \(url.absoluteString)."
		case .valueMissing(let name, let url):
			return "Fiscal Monitor value '\(name)' missing from \(url.absoluteString)."
		case .invalidPeriod(let url):
			return "Fiscal Monitor period could not be inferred from \(url.absoluteString)."
		}
	}
}

struct FiscalMonitorService {
	private let indexURL = URL(string: "https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor.html")!
	private let session: URLSession
	private let calendar: Calendar

	init(session: URLSession = .shared, calendar: Calendar = Calendar(identifier: .gregorian)) {
		self.session = session
		self.calendar = calendar
	}

	func currentFiscalYearEntries() async throws -> [FiscalMonitorParsedEntry] {
		let issues = try await currentFiscalYearIssues()
		var entries: [FiscalMonitorParsedEntry] = []
		for issue in issues.sorted(by: { fiscalMonthOrder($0.month) < fiscalMonthOrder($1.month) }) {
			let (data, _) = try await session.data(from: issue.url)
			guard let html = String(data: data, encoding: .utf8) else {
				throw FiscalMonitorServiceError.invalidHTML
			}
			entries.append(try Self.parseIssue(html: html, url: issue.url))
		}
		return entries
	}

	func currentFiscalYearIssues() async throws -> [FiscalMonitorIssue] {
		let (data, _) = try await session.data(from: indexURL)
		guard let html = String(data: data, encoding: .utf8) else {
			throw FiscalMonitorServiceError.invalidHTML
		}
		let issues = try Self.parseIssueLinks(html: html, baseURL: indexURL)
		guard let latestFiscalYear = issues.map(\.fiscalYearStart).max() else {
			throw FiscalMonitorServiceError.noIssueLinks
		}
		return issues
			.filter { $0.fiscalYearStart == latestFiscalYear }
			.sorted(by: { fiscalMonthOrder($0.month) < fiscalMonthOrder($1.month) })
	}

	static func parseIssueLinks(html: String, baseURL: URL) throws -> [FiscalMonitorIssue] {
		guard let doc = try? HTML(html: html, url: baseURL.absoluteString, encoding: .utf8) else {
			throw FiscalMonitorServiceError.invalidHTML
		}
		let pattern = #"/fiscal-monitor/(\d{4})/(\d{2})\.html"#
		let regex = try NSRegularExpression(pattern: pattern)
		var issues: Set<FiscalMonitorIssue> = []

		for link in doc.css("a") {
			guard let href = link["href"],
				  let match = regex.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
				  let yearRange = Range(match.range(at: 1), in: href),
				  let monthRange = Range(match.range(at: 2), in: href),
				  let year = Int(href[yearRange]),
				  let month = Int(href[monthRange]),
				  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
				continue
			}
			issues.insert(FiscalMonitorIssue(year: year, month: month, url: url))
		}
		return Array(issues)
	}

	static func parseIssue(html: String, url: URL) throws -> FiscalMonitorParsedEntry {
		guard let doc = try? HTML(html: html, url: url.absoluteString, encoding: .utf8) else {
			throw FiscalMonitorServiceError.invalidHTML
		}
		let title = normalized(doc.at_css("title")?.text).replacingOccurrences(of: " - Canada.ca", with: "")
		let publicationDate = parseMetadataDate(doc.at_xpath("//meta[@name='dcterms.issued']")?["content"])
			?? parseMetadataDate(doc.at_xpath("//meta[@name='dcterms.modified']")?["content"])
			?? Date()
		let issue = try issueFrom(url: url)
		guard let table = doc.css("table").first(where: { normalized($0.at_css("caption")?.text).contains("Summary statement of transactions") }) else {
			throw FiscalMonitorServiceError.summaryTableMissing(url)
		}

		let values = tableValues(table)
		let revenue = try currentMonthValue("Revenues", values: values, url: url)
		let programExpenses = abs(try currentMonthValue("Program expenses, excluding net actuarial losses", values: values, url: url))
		let publicDebtCharges = abs(try currentMonthValue("Public debt charges", values: values, url: url))
		let netActuarialLosses = abs(try currentMonthValue("Net actuarial losses", values: values, url: url))
		let balance = try currentMonthValue("Budgetary balance (deficit/surplus)", values: values, url: url)
		let yearToDateBalance = try yearToDateValue("Budgetary balance (deficit/surplus)", values: values, url: url)
		let annualProjection = parseAnnualProjection(doc)

		return FiscalMonitorParsedEntry(
			fiscalYearStart: issue.fiscalYearStart,
			month: issue.month,
			monthName: monthName(issue.month),
			periodDate: periodDate(year: issue.year, month: issue.month),
			publicationDate: publicationDate,
			revenueMillions: revenue,
			programExpenseMillions: programExpenses,
			publicDebtChargesMillions: publicDebtCharges,
			netActuarialLossesMillions: netActuarialLosses,
			budgetaryBalanceMillions: balance,
			yearToDateBudgetaryBalanceMillions: yearToDateBalance,
			annualBudgetProjectionMillions: annualProjection,
			sourceTitle: title.isEmpty ? "The Fiscal Monitor" : title,
			sourceURL: url.absoluteString
		)
	}

	private static func tableValues(_ table: XMLElement) -> [String: [Double]] {
		var rows: [String: [Double]] = [:]
		for row in table.css("tr") {
			let key = normalized(row.at_css("th")?.text)
			guard !key.isEmpty else { continue }
			let numbers = row.css("td").compactMap { parseAmount($0.text) }
			if !numbers.isEmpty {
				rows[key] = numbers
			}
		}
		return rows
	}

	private static func currentMonthValue(_ row: String, values: [String: [Double]], url: URL) throws -> Double {
		guard let numbers = values[row], numbers.count >= 2 else {
			throw FiscalMonitorServiceError.valueMissing(row, url)
		}
		return numbers[1]
	}

	private static func yearToDateValue(_ row: String, values: [String: [Double]], url: URL) throws -> Double {
		guard let numbers = values[row], numbers.count >= 4 else {
			throw FiscalMonitorServiceError.valueMissing("\(row) year-to-date", url)
		}
		return numbers[3]
	}

	private static func parseAnnualProjection(_ doc: HTMLDocument) -> Double? {
		for row in doc.css("tr") {
			let key = normalized(row.at_css("th")?.text)
			guard key.contains("Actual/projected annual budgetary balance") else { continue }
			let numbers = row.css("td").compactMap { parseAmount($0.text) }
			return numbers.count >= 2 ? numbers[1] : numbers.last
		}
		return nil
	}

	private static func issueFrom(url: URL) throws -> FiscalMonitorIssue {
		let path = url.path
		let pattern = #"/fiscal-monitor/(\d{4})/(\d{2})\.html"#
		let regex = try NSRegularExpression(pattern: pattern)
		guard let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
			  let yearRange = Range(match.range(at: 1), in: path),
			  let monthRange = Range(match.range(at: 2), in: path),
			  let year = Int(path[yearRange]),
			  let month = Int(path[monthRange]) else {
			throw FiscalMonitorServiceError.invalidPeriod(url)
		}
		return FiscalMonitorIssue(year: year, month: month, url: url)
	}

	private static func periodDate(year: Int, month: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
	}

	private static func parseMetadataDate(_ raw: String?) -> Date? {
		guard let raw else { return nil }
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_CA_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.date(from: raw)
	}

	private static func parseAmount(_ raw: String?) -> Double? {
		let cleaned = normalized(raw)
			.replacingOccurrences(of: ",", with: "")
			.replacingOccurrences(of: "$", with: "")
			.replacingOccurrences(of: "\u{00a0}", with: "")
		return Double(cleaned)
	}

	private static func normalized(_ raw: String?) -> String {
		(raw ?? "")
			.replacingOccurrences(of: "\u{00a0}", with: " ")
			.replacingOccurrences(of: #"[\s\r\n\t]+"#, with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func monthName(_ month: Int) -> String {
		DateFormatter().monthSymbols[month - 1]
	}

	private func fiscalMonthOrder(_ month: Int) -> Int {
		month >= 4 ? month - 4 : month + 8
	}

	private static func fiscalMonthOrder(_ month: Int) -> Int {
		month >= 4 ? month - 4 : month + 8
	}
}
