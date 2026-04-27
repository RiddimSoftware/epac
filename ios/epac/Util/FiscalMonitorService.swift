import Foundation
import Kanna

struct FiscalMonitorParsedEntry: Identifiable, Equatable {
	let id: String
	let fiscalYear: String
	let month: Date
	let publicationDate: Date
	let revenueMillions: Double
	let expenseMillions: Double
	let budgetaryBalanceMillions: Double
	let yearToDateBalanceMillions: Double
	let annualBudgetProjectionMillions: Double?
	let sourceTitle: String
	let sourceURL: URL
}

struct FiscalMonitorService {
	private static let baseURL = URL(string: "https://www.canada.ca")!
	private static let calendar = Calendar(identifier: .gregorian)

	static func fetchCurrentFiscalYearEntries(now: Date = Date()) async throws -> [FiscalMonitorParsedEntry] {
		let candidates = candidateIssueURLs(now: now)
		var entries: [FiscalMonitorParsedEntry] = []
		for url in candidates {
			var request = URLRequest(url: url, timeoutInterval: 30)
			request.setValue("text/html", forHTTPHeaderField: "Accept")
			let data: Data
			let response: URLResponse
			do {
				(data, response) = try await URLSession.shared.data(for: request)
			} catch {
				continue
			}
			guard let http = response as? HTTPURLResponse else { continue }
			if http.statusCode == 404 { continue }
			guard (200..<300).contains(http.statusCode),
				  let html = String(data: data, encoding: .utf8) else { continue }
			if let entry = try? parseIssueHTML(html, sourceURL: url) {
				entries.append(entry)
			}
		}
		return entries.sorted { $0.month < $1.month }
	}

	static func parseIssueHTML(_ html: String, sourceURL: URL) throws -> FiscalMonitorParsedEntry {
		guard let doc = try? HTML(html: html, url: nil, encoding: .utf8) else {
			throw URLError(.cannotParseResponse)
		}
		let text = normalizeWhitespace(doc.text ?? "")
		let sourceTitle = doc.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "The Fiscal Monitor"
		let issue = try parseIssueMonth(from: sourceTitle, fallbackText: text)
		let publicationDate = try parsePublicationDate(from: text)
		let table1 = try parseSummaryStatement(from: text)
		let annualProjection = parseAnnualProjection(from: text)
		let fiscalYear = fiscalYearLabel(for: issue)
		let officialSourceURL = pdfSourceURL(from: html) ?? sourceURL

		return FiscalMonitorParsedEntry(
			id: issue.formatted(.iso8601.year().month()),
			fiscalYear: fiscalYear,
			month: issue,
			publicationDate: publicationDate,
			revenueMillions: table1.revenue,
			expenseMillions: table1.expense,
			budgetaryBalanceMillions: table1.balance,
			yearToDateBalanceMillions: table1.ytdBalance,
			annualBudgetProjectionMillions: annualProjection,
			sourceTitle: "Finance Canada Fiscal Monitor, \(issue.formatted(.dateTime.month(.wide).year()))",
			sourceURL: officialSourceURL
		)
	}

	private static func candidateIssueURLs(now: Date) -> [URL] {
		let components = calendar.dateComponents([.year, .month], from: now)
		let year = components.year ?? 2026
		let month = components.month ?? 1
		let fiscalStartYear = month <= 6 ? year - 1 : year
		let months = (4...12).map { (fiscalStartYear, $0) } + (1...3).map { (fiscalStartYear + 1, $0) }
		return months.compactMap { year, month in
			URL(string: String(format: "/en/department-finance/services/publications/fiscal-monitor/%04d/%02d.html", year, month), relativeTo: baseURL)
		}
	}

	private static func parseIssueMonth(from title: String, fallbackText: String) throws -> Date {
		let joined = "\(title) \(fallbackText)"
		let regex = try NSRegularExpression(pattern: "Fiscal Monitor - ([A-Za-z]+) (\\d{4})")
		guard let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
			  let monthRange = Range(match.range(at: 1), in: joined),
			  let yearRange = Range(match.range(at: 2), in: joined) else {
			throw URLError(.cannotParseResponse)
		}
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "MMMM yyyy"
		guard let date = formatter.date(from: "\(joined[monthRange]) \(joined[yearRange])") else {
			throw URLError(.cannotParseResponse)
		}
		return date
	}

	private static func parsePublicationDate(from text: String) throws -> Date {
		let regex = try NSRegularExpression(pattern: "Page details (\\d{4}-\\d{2}-\\d{2})")
		guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
			  let range = Range(match.range(at: 1), in: text) else {
			throw URLError(.cannotParseResponse)
		}
		return try Date(String(text[range]), strategy: .iso8601.year().month().day())
	}

	private static func parseSummaryStatement(from text: String) throws -> (revenue: Double, expense: Double, balance: Double, ytdBalance: Double) {
		let revenue = try captureLastTwoNumbers(after: "Revenues", before: "Expenses", in: text)
		let balance = try captureLastTwoNumbers(after: "Budgetary balance \\(deficit/surplus\\)", before: "Non-budgetary transactions", in: text)
		return (revenue.currentMonth, revenue.currentMonth - balance.currentMonth, balance.currentMonth, balance.yearToDate)
	}

	private static func parseAnnualProjection(from text: String) -> Double? {
		guard let values = try? captureNumbers(after: "Actual/projected annual budgetary balance", before: "Table 1", in: text),
			  values.count >= 2 else {
			return nil
		}
		return values.first == 1 && values.count >= 3 ? values[2] : values[1]
	}

	private static func pdfSourceURL(from html: String) -> URL? {
		guard let regex = try? NSRegularExpression(pattern: #"href="([^"]+\.pdf)""#, options: [.caseInsensitive]),
			  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
			  let range = Range(match.range(at: 1), in: html) else {
			return nil
		}
		return URL(string: String(html[range]), relativeTo: baseURL)?.absoluteURL
	}

	private static func captureLastTwoNumbers(after startPattern: String, before endPattern: String, in text: String) throws -> (currentMonth: Double, yearToDate: Double) {
		let numbers = try captureNumbers(after: startPattern, before: endPattern, in: text)
		guard numbers.count >= 4 else { throw URLError(.cannotParseResponse) }
		return (numbers[1], numbers[3])
	}

	private static func captureNumbers(after startPattern: String, before endPattern: String, in text: String) throws -> [Double] {
		let regex = try NSRegularExpression(pattern: "\(startPattern) (.*?) \(endPattern)")
		guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
			  let range = Range(match.range(at: 1), in: text) else {
			throw URLError(.cannotParseResponse)
		}
		return numberTokens(in: String(text[range]))
	}

	private static func numberTokens(in text: String) -> [Double] {
		let pattern = "-?\\d{1,3}(?:,\\d{3})*|-"
		let regex = try? NSRegularExpression(pattern: pattern)
		let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
		return matches.compactMap { match in
			guard let range = Range(match.range, in: text) else { return nil }
			let token = String(text[range])
			if token == "-" { return 0 }
			return Double(token.replacingOccurrences(of: ",", with: ""))
		}
	}

	private static func fiscalYearLabel(for date: Date) -> String {
		let year = calendar.component(.year, from: date)
		let month = calendar.component(.month, from: date)
		let start = month >= 4 ? year : year - 1
		return "\(start)-\(String(format: "%02d", (start + 1) % 100))"
	}

	private static func normalizeWhitespace(_ text: String) -> String {
		text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
