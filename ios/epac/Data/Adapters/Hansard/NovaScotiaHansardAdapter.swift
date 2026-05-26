//
//  NovaScotiaHansardAdapter.swift
//  epac
//

import Foundation
import Kanna

@MainActor
struct NovaScotiaHansardAdapter: HansardRepository, HTMLHansardScaffold {
	typealias FetchData = @Sendable (URL) async throws -> Data
	typealias Sleep = @Sendable (Duration) async throws -> Void
	typealias PersistTranscript = @MainActor @Sendable (HansardTranscript) async throws -> Void

	let jurisdiction: Jurisdiction = .novaScotia

	private let fetchData: FetchData
	private let sleep: Sleep
	private let persistTranscript: PersistTranscript

	init(
		fetchData: @escaping FetchData = NovaScotiaHansardHTTPClient.fetchData,
		sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
		persistTranscript: @escaping PersistTranscript = { _ in throw NovaScotiaHansardAdapterError.persistenceNotConfigured }
	) {
		self.fetchData = fetchData
		self.sleep = sleep
		self.persistTranscript = persistTranscript
	}

	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		try requireSupported(jurisdiction)
		let source = try await transcriptSource(for: sittingDate)
		return try await fetchHTMLTranscript(from: source, sittingDate: sittingDate)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
		try requireSupported(jurisdiction)
		guard startDate <= endDate else { return [] }
		let sources = try await crawlIndexPages { page in
			page.hasAnyDate(before: startDate)
		}
		return sources
			.map(\.sittingDate)
			.filter { startDate <= $0 && $0 <= endDate }
			.removingDuplicates()
			.sorted()
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		try requireSupported(transcript.jurisdiction)
		try await persistTranscript(transcript)
	}

	private func transcriptSource(for sittingDate: Date) async throws -> NovaScotiaHansardSource {
		let sources = try await crawlIndexPages { page in
			page.source(on: sittingDate) != nil || page.hasAnyDate(before: sittingDate)
		}
		guard let source = sources.first(where: { Calendar.utc.isDate($0.sittingDate, inSameDayAs: sittingDate) }) else {
			throw NovaScotiaHansardAdapterError.transcriptNotFound(sittingDate)
		}
		return source
	}

	private func crawlIndexPages(shouldStop: (NovaScotiaHansardIndexPage) -> Bool) async throws -> [NovaScotiaHansardSource] {
		var sources: [NovaScotiaHansardSource] = []
		var pageURL: URL? = try NovaScotiaHansardURLBuilder.indexURL(page: nil)
		var visitedPageCount = 0
		while let url = pageURL, visitedPageCount < NovaScotiaHansardConstants.maximumIndexPages {
			let page = try await fetchSittingIndexPage(at: url)
			sources.append(contentsOf: page.sources)
			if shouldStop(page) { return sources }
			pageURL = page.nextPageURL
			visitedPageCount += 1
			if pageURL != nil {
				try await sleep(NovaScotiaHansardConstants.requestSpacing)
			}
		}
		return sources
	}

	private func fetchSittingIndexPage(at url: URL) async throws -> NovaScotiaHansardIndexPage {
		let data = try await fetchData(url)
		let html = try NovaScotiaHansardTextDecoder.string(from: data)
		return try NovaScotiaHansardIndexParser.parse(html: html, baseURL: url)
	}

	private func fetchHTMLTranscript(
		from source: NovaScotiaHansardSource,
		sittingDate: Date
	) async throws -> HansardTranscript {
		try await sleep(NovaScotiaHansardConstants.requestSpacing)
		let data = try await fetchData(source.htmlURL)
		let html = try NovaScotiaHansardTextDecoder.string(from: data)
		let subjects = try NovaScotiaHTMLHansardParser(scaffold: self).parse(html: html)
		return makeTranscript(
			sittingDate: sittingDate,
			legislatureNumber: source.legislatureNumber,
			sourceURL: source.htmlURL,
			subjects: subjects
		)
	}

	private func requireSupported(_ jurisdiction: Jurisdiction) throws {
		guard jurisdiction == .novaScotia else {
			throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
		}
	}
}

enum NovaScotiaHansardAdapterError: Error, Equatable {
	case invalidIndexURL
	case transcriptNotFound(Date)
	case unparseableIndex
	case unparseableTranscript
	case persistenceNotConfigured
}

private enum NovaScotiaHansardConstants {
	static let host = "nslegislature.ca"
	static let currentAssemblyPath = "/legislative-business/hansard-debates/assembly-65-session-1"
	static let sourceLinkPathFragment = "/legislative-business/hansard-debates/assembly-65-session-1/house_"
	static let requestTimeout: TimeInterval = 20
	static let requestSpacing: Duration = .seconds(1)
	static let maximumIndexPages = 20
	static let minimumSpeechWords = 2
	static let assemblyPathComponentCount = 4
	static let legislaturePathIndex = 1
	static let sessionPathIndex = 3
	static let minimumHeadingLetters = 3
	static let successStatusLowerBound = 200
	static let successStatusUpperBound = 300

	static var successStatusCodes: Range<Int> {
		successStatusLowerBound..<successStatusUpperBound
	}
}

private enum NovaScotiaHansardURLBuilder {
	static func indexURL(page: Int?) throws -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = NovaScotiaHansardConstants.host
		components.path = NovaScotiaHansardConstants.currentAssemblyPath
		components.queryItems = page.map { [URLQueryItem(name: "page", value: "\($0)")] }
		guard let url = components.url else {
			throw NovaScotiaHansardAdapterError.invalidIndexURL
		}
		return url
	}
}

private enum NovaScotiaHansardHTTPClient {
	static func fetchData(from url: URL) async throws -> Data {
		var request = URLRequest(url: url, timeoutInterval: NovaScotiaHansardConstants.requestTimeout)
		request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
		let (data, response) = try await NetworkService.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse,
		      NovaScotiaHansardConstants.successStatusCodes.contains(httpResponse.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}
}

private struct NovaScotiaHansardSource: Equatable {
	let sittingDate: Date
	let legislatureNumber: Int
	let sessionNumber: Int
	let htmlURL: URL
}

private struct NovaScotiaHansardIndexPage {
	let sources: [NovaScotiaHansardSource]
	let nextPageURL: URL?

	func source(on sittingDate: Date) -> NovaScotiaHansardSource? {
		sources.first { Calendar.utc.isDate($0.sittingDate, inSameDayAs: sittingDate) }
	}

	func hasAnyDate(before sittingDate: Date) -> Bool {
		sources.contains { $0.sittingDate < sittingDate }
	}
}

private enum NovaScotiaHansardIndexParser {
	static func parse(html: String, baseURL: URL) throws -> NovaScotiaHansardIndexPage {
		guard let document = try? HTML(html: html, encoding: .utf8) else {
			throw NovaScotiaHansardAdapterError.unparseableIndex
		}
		return NovaScotiaHansardIndexPage(
			sources: sources(in: document, baseURL: baseURL),
			nextPageURL: nextPageURL(in: document, baseURL: baseURL)
		)
	}

	private static func sources(in document: HTMLDocument, baseURL: URL) -> [NovaScotiaHansardSource] {
		document.xpath(sourceLinkXPath)
			.compactMap { NovaScotiaHansardSource(link: $0, baseURL: baseURL) }
			.sorted { $0.sittingDate > $1.sittingDate }
	}

	private static func nextPageURL(in document: HTMLDocument, baseURL: URL) -> URL? {
		document
			.xpath("//a[@title='Go to next page']")
			.compactMap { $0["href"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL } }
			.first
	}

	private static let sourceLinkXPath =
		"//a[contains(@href, '\(NovaScotiaHansardConstants.sourceLinkPathFragment)')]"
}

private extension NovaScotiaHansardSource {
	init?(link: XMLElement, baseURL: URL) {
		guard let dateText = link.text,
		      let sittingDate = NovaScotiaHansardDateFormatter.index.date(from: dateText.normalizedWhitespace),
		      let href = link["href"],
		      let htmlURL = URL(string: href, relativeTo: baseURL)?.absoluteURL,
		      let assembly = NovaScotiaAssemblyPath(url: htmlURL) else {
			return nil
		}
		self.sittingDate = sittingDate
		legislatureNumber = assembly.legislatureNumber
		sessionNumber = assembly.sessionNumber
		self.htmlURL = htmlURL
	}
}

private struct NovaScotiaAssemblyPath {
	let legislatureNumber: Int
	let sessionNumber: Int

	init?(url: URL) {
		let pathSegment = url.path.split(separator: "/").first { segment in
			segment.hasPrefix("assembly-") && segment.contains("-session-")
		}
		guard let pathSegment else { return nil }
		let parts = pathSegment.split(separator: "-")
		guard parts.count == NovaScotiaHansardConstants.assemblyPathComponentCount,
		      let legislatureNumber = Int(parts[NovaScotiaHansardConstants.legislaturePathIndex]),
		      let sessionNumber = Int(parts[NovaScotiaHansardConstants.sessionPathIndex]) else {
			return nil
		}
		self.legislatureNumber = legislatureNumber
		self.sessionNumber = sessionNumber
	}
}

private struct NovaScotiaHTMLHansardParser {
	private let scaffold: any HTMLHansardScaffold

	init(scaffold: any HTMLHansardScaffold) {
		self.scaffold = scaffold
	}

	func parse(html: String) throws -> [SubjectOfBusinessRecord] {
		guard let document = try? HTML(html: html, encoding: .utf8) else {
			throw NovaScotiaHansardAdapterError.unparseableTranscript
		}
		let builder = NovaScotiaHTMLSubjectBuilder(scaffold: scaffold)
		for element in bodyElements(in: document) {
			builder.consume(element)
		}
		let subjects = builder.subjects()
		guard !subjects.isEmpty else {
			throw NovaScotiaHansardAdapterError.unparseableTranscript
		}
		return subjects
	}

	private func bodyElements(in document: HTMLDocument) -> [XMLElement] {
		let elements = Array(document.xpath(
			"//table[@id='hansard_toc']/following::p|//table[@id='hansard_toc']/following::blockquote"
		))
		if !elements.isEmpty { return elements }
		return Array(document.xpath("//div[contains(@class, 'hsd_body')]//p|//div[contains(@class, 'hsd_body')]//blockquote"))
	}
}

private final class NovaScotiaHTMLSubjectBuilder {
	private let scaffold: any HTMLHansardScaffold
	private var records: [SubjectOfBusinessRecord] = []
	private var currentTitle = "Debates"
	private var currentSpeeches: [SpeechMessageRecord] = []
	private var currentSpeaker: NovaScotiaSpeechStart?
	private var currentSpeechParagraphs: [String] = []
	private var subjectIndex = 0
	private var speechIndex = 0

	init(scaffold: any HTMLHansardScaffold) {
		self.scaffold = scaffold
	}

	func consume(_ element: XMLElement) {
		let text = scaffold.normalizedText(element.text ?? "")
		guard !text.isEmpty, !NovaScotiaHansardTextClassifier.shouldSkip(text) else { return }
		if let speechStart = NovaScotiaSpeechLineParser.parse(element, scaffold: scaffold) {
			startSpeech(speechStart)
			return
		}
		if NovaScotiaHansardTextClassifier.isHeading(element: element, text: text) {
			consumeHeading(text)
			return
		}
		appendToCurrentSpeech(text)
	}

	func subjects() -> [SubjectOfBusinessRecord] {
		flushSpeech()
		flushSubject()
		return records
	}

	private func consumeHeading(_ text: String) {
		flushSpeech()
		flushSubject()
		currentTitle = text.trimmingBoundaryCharacters
		subjectIndex += 1
	}

	private func startSpeech(_ speechStart: NovaScotiaSpeechStart) {
		flushSpeech()
		currentSpeaker = speechStart
		currentSpeechParagraphs = speechStart.text.isEmpty ? [] : [speechStart.text]
	}

	private func appendToCurrentSpeech(_ text: String) {
		guard currentSpeaker != nil else { return }
		currentSpeechParagraphs.append(text)
	}

	private func flushSpeech() {
		guard let currentSpeaker,
		      !currentSpeechParagraphs.isEmpty else {
			resetCurrentSpeech()
			return
		}
		let text = currentSpeechParagraphs.joined(separator: "\n\n")
		guard text.split(whereSeparator: \.isWhitespace).count >= NovaScotiaHansardConstants.minimumSpeechWords else {
			resetCurrentSpeech()
			return
		}
		speechIndex += 1
		currentSpeeches.append(scaffold.makeSpeech(
			interventionID: currentSpeaker.interventionID ?? generatedInterventionID(for: currentSpeaker),
			speakerText: currentSpeaker.speakerText,
			speakerMemberID: currentSpeaker.speakerMemberID,
			text: text
		))
		resetCurrentSpeech()
	}

	private func flushSubject() {
		guard !currentSpeeches.isEmpty else { return }
		records.append(scaffold.makeSubject(
			id: "ns-subject-\(subjectIndex)-\(currentTitle.slug)",
			title: currentTitle,
			speeches: currentSpeeches
		))
		currentSpeeches = []
	}

	private func generatedInterventionID(for speechStart: NovaScotiaSpeechStart) -> String {
		"ns-\(subjectIndex)-\(speechIndex)-\(speechStart.speakerText.slug)"
	}

	private func resetCurrentSpeech() {
		currentSpeaker = nil
		currentSpeechParagraphs = []
	}
}

private struct NovaScotiaSpeechStart {
	let interventionID: String?
	let speakerText: String
	let speakerMemberID: String?
	let text: String
}

private enum NovaScotiaSpeechLineParser {
	static func parse(_ element: XMLElement, scaffold: any HTMLHansardScaffold) -> NovaScotiaSpeechStart? {
		let text = scaffold.normalizedText(element.text ?? "")
		guard let speechParts = speechParts(from: text) else { return nil }
		let interventionID = interventionID(in: element)
		let memberLink = firstMemberLink(in: element)
		guard interventionID != nil || memberLink != nil else { return nil }
		let speakerText = speakerText(from: memberLink, fallback: speechParts.speaker, scaffold: scaffold)
		guard !speakerText.isEmpty else { return nil }
		return NovaScotiaSpeechStart(
			interventionID: interventionID,
			speakerText: speakerText,
			speakerMemberID: memberID(from: memberLink),
			text: speechParts.text
		)
	}

	private static func speechParts(from text: String) -> (speaker: String, text: String)? {
		guard let colonIndex = text.firstIndex(of: ":") else { return nil }
		return (
			speaker: String(text[..<colonIndex]).cleanedSpeakerPrefix,
			text: String(text[text.index(after: colonIndex)...]).trimmingSpeechLead
		)
	}

	private static func interventionID(in element: XMLElement) -> String? {
		element
			.xpath(".//a[@name]")
			.compactMap(\.["name"])
			.first { !$0.isPageAnchorName }
	}

	private static func firstMemberLink(in element: XMLElement) -> XMLElement? {
		element
			.xpath(".//a[@href]")
			.first { link in
				guard let href = link["href"] else { return false }
				return href.contains("/members/profiles/") || href.contains("/members/speaker/")
			}
	}

	private static func speakerText(
		from memberLink: XMLElement?,
		fallback: String,
		scaffold: any HTMLHansardScaffold
	) -> String {
		let rawSpeaker = memberLink.flatMap(\.text) ?? fallback
		return scaffold.normalizedText(rawSpeaker).displaySpeakerName
	}

	private static func memberID(from memberLink: XMLElement?) -> String? {
		guard let href = memberLink?["href"],
		      href.contains("/members/profiles/") else {
			return nil
		}
		return URL(string: href)?.pathComponents.last
	}
}

private enum NovaScotiaHansardTextClassifier {
	static func shouldSkip(_ text: String) -> Bool {
		isPageMarker(text) || isTimestamp(text) || isHeaderMetadata(text)
	}

	static func isHeading(element: XMLElement, text: String) -> Bool {
		element.at_xpath(".//b") != nil && isUppercaseHeading(text)
	}

	private static func isPageMarker(_ text: String) -> Bool {
		text.hasPrefix("[Page ")
	}

	private static func isTimestamp(_ text: String) -> Bool {
		text.hasPrefix("[") && text.hasSuffix("]") && (text.contains(" a.m.") || text.contains(" p.m."))
	}

	private static func isHeaderMetadata(_ text: String) -> Bool {
		text.hasPrefix("HALIFAX,") || text.contains("General Assembly") || text == "First Session"
	}

	private static func isUppercaseHeading(_ text: String) -> Bool {
		let letters = text.filter(\.isLetter)
		return letters.count >= NovaScotiaHansardConstants.minimumHeadingLetters && !letters.contains { $0.isLowercase }
	}
}

private enum NovaScotiaHansardTextDecoder {
	static func string(from data: Data) throws -> String {
		if let text = String(data: data, encoding: .utf8) {
			return text
		}
		if let text = String(data: data, encoding: .windowsCP1252) {
			return text
		}
		throw NovaScotiaHansardAdapterError.unparseableTranscript
	}
}

private enum NovaScotiaHansardDateFormatter {
	static let index: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = .utc
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = .utc
		formatter.dateFormat = "yyyy-MMM-d"
		return formatter
	}()
}

private extension String {
	var cleanedSpeakerPrefix: String {
		replacingOccurrences(of: "\u{00ab}", with: " ")
			.replacingOccurrences(of: "\u{00bb}", with: " ")
			.replacingOccurrences(of: "Previous", with: " ")
			.replacingOccurrences(of: "Next", with: " ")
			.normalizedWhitespace
	}

	var displaySpeakerName: String {
		let text = trimmingCharacters(in: .whitespacesAndNewlines)
		return text == text.uppercased() ? text.lowercased().capitalized(with: Locale(identifier: "en_CA")) : text
	}

	var isPageAnchorName: Bool {
		let lowercasedName = lowercased()
		return lowercasedName.hasPrefix("hpage") || lowercasedName.hasPrefix("ipage") || lowercasedName == "content"
	}

	var normalizedWhitespace: String {
		replacingOccurrences(of: "\u{00a0}", with: " ")
			.split { $0.isWhitespace }
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var slug: String {
		let allowed = CharacterSet.alphanumerics
		let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
		return String(scalars)
			.lowercased()
			.split(separator: "-")
			.joined(separator: "-")
	}

	var trimmingBoundaryCharacters: String {
		trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
	}

	var trimmingSpeechLead: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

private extension Calendar {
	static var utc: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .utc
		return calendar
	}
}

private extension TimeZone {
	static let utc = TimeZone(secondsFromGMT: 0)!
}

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
