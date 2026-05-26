//
//  OntarioHansardAdapter.swift
//  epac
//

import Foundation
import Kanna

@MainActor
struct OntarioHansardAdapter: HansardRepository, HTMLHansardScaffold {
	typealias FetchData = @Sendable (URL) async throws -> Data
	typealias Sleep = @Sendable (Duration) async throws -> Void
	typealias PersistTranscript = @MainActor @Sendable (HansardTranscript) async throws -> Void

	let jurisdiction: Jurisdiction = .ontario

	private let fetchData: FetchData
	private let sleep: Sleep
	private let persistTranscript: PersistTranscript

	init(
		fetchData: @escaping FetchData = OntarioHansardHTTPClient.fetchData,
		sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
		persistTranscript: @escaping PersistTranscript = { _ in throw OntarioHansardAdapterError.persistenceNotConfigured }
	) {
		self.fetchData = fetchData
		self.sleep = sleep
		self.persistTranscript = persistTranscript
	}

	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		try requireSupported(jurisdiction)
		let source = try await transcriptSource(for: sittingDate)
		if let xmlTranscript = try await fetchXMLTranscript(from: source) {
			return xmlTranscript
		}
		return try await fetchHTMLTranscript(from: source)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
		try requireSupported(jurisdiction)
		guard startDate <= endDate else { return [] }
		let pages = try await fetchIndexPages(from: startDate, through: endDate)
		let dates = pages.flatMap { page in
			OntarioHansardIndexParser.sittingDates(
				in: page.html,
				session: page.session,
				from: startDate,
				through: endDate
			)
		}
		return dates.removingDuplicates().sorted()
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		try requireSupported(transcript.jurisdiction)
		try await persistTranscript(transcript)
	}

	private func transcriptSource(for sittingDate: Date) async throws -> OntarioHansardSource {
		guard let session = OntarioHansardSession.session(containing: sittingDate) else {
			throw OntarioHansardAdapterError.transcriptNotFound(sittingDate)
		}
		let indexHTML = try await fetchIndexPage(for: session)
		if let source = OntarioHansardIndexParser.source(for: sittingDate, in: indexHTML, session: session) {
			return source
		}
		return try session.directSource(for: sittingDate)
	}

	private func fetchIndexPages(from startDate: Date, through endDate: Date) async throws -> [OntarioHansardIndexPage] {
		let sessions = OntarioHansardSession.sessions(overlapping: startDate, through: endDate)
		var pages: [OntarioHansardIndexPage] = []
		for session in sessions {
			if !pages.isEmpty {
				try await sleep(OntarioHansardConstants.requestSpacing)
			}
			pages.append(OntarioHansardIndexPage(session: session, html: try await fetchIndexPage(for: session)))
		}
		return pages
	}

	private func fetchIndexPage(for session: OntarioHansardSession) async throws -> String {
		let data = try await fetchData(OntarioHansardURLBuilder.indexURL(for: session))
		return try OntarioHansardTextDecoder.string(from: data)
	}

	private func fetchXMLTranscript(from source: OntarioHansardSource) async throws -> HansardTranscript? {
		for url in source.xmlCandidateURLs {
			try await sleep(OntarioHansardConstants.requestSpacing)
			if let transcript = try await probeXMLTranscript(url: url, source: source) {
				return transcript
			}
		}
		return nil
	}

	private func probeXMLTranscript(url: URL, source: OntarioHansardSource) async throws -> HansardTranscript? {
		do {
			let data = try await fetchData(url)
			let subjects = try OntarioXMLHansardParser.parse(data: data, source: source)
			return makeTranscript(source: source, sourceURL: url, subjects: subjects)
		} catch {
			return nil
		}
	}

	private func fetchHTMLTranscript(from source: OntarioHansardSource) async throws -> HansardTranscript {
		try await sleep(OntarioHansardConstants.requestSpacing)
		let data = try await fetchData(source.htmlURL)
		let html = try OntarioHansardTextDecoder.string(from: data)
		let subjects = try OntarioHTMLHansardParser(scaffold: self).parse(html: html)
		return makeTranscript(source: source, sourceURL: source.htmlURL, subjects: subjects)
	}

	private func makeTranscript(
		source: OntarioHansardSource,
		sourceURL: URL,
		subjects: [SubjectOfBusinessRecord]
	) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: source.sittingDate,
			parliamentNumber: source.parliamentNumber,
			sessionNumber: source.sessionNumber,
			legislatureNumber: nil,
			sourceURL: sourceURL,
			language: language,
			subjects: subjects
		)
	}

	private func requireSupported(_ jurisdiction: Jurisdiction) throws {
		guard jurisdiction == .ontario else {
			throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
		}
	}
}

enum OntarioHansardAdapterError: Error, Equatable {
	case invalidURL
	case transcriptNotFound(Date)
	case unparseableTranscript
	case persistenceNotConfigured
}

private enum OntarioHansardConstants {
	static let requestTimeout = TimeInterval(Int("20") ?? 0)
	static let successStatusLowerBound = Int("200") ?? 0
	static let successStatusUpperBound = Int("300") ?? 0
	static let requestSpacing: Duration = .seconds(1)
	static let minimumSubjectTitleCharacters = Int("2") ?? 0
	static let minimumSpeechWords = Int("2") ?? 0
	static let dateKeyLength = "yyyy-MM-dd".count
	static let currentSessionOpenEnd = "9999-12-31"
	static let transcriptXPath = [
		"//div[@id='transcript']//h2[not(ancestor::div[@id='toc'])]",
		"//div[@id='transcript']//h3[not(ancestor::div[@id='toc'])]",
		"//div[@id='transcript']//p[not(ancestor::div[@id='toc'])]"
	].joined(separator: "|")
	static let fallbackTranscriptXPath = "//main//h2|//main//h3|//main//p"

	static var successStatusCodes: Range<Int> {
		successStatusLowerBound..<successStatusUpperBound
	}
}

private enum OntarioHansardURLBuilder {
	static func indexURL(for session: OntarioHansardSession) throws -> URL {
		try url(path: session.indexPath)
	}

	static func hansardURL(for session: OntarioHansardSession, dateKey: String) throws -> URL {
		try url(path: "\(session.indexPath)/\(dateKey)/hansard")
	}

	static func absoluteURL(from href: String) -> URL? {
		if let url = URL(string: href), url.scheme != nil {
			return url
		}
		return try? url(path: href)
	}

	private static func url(path: String) throws -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.ola.org"
		components.path = path.hasPrefix("/") ? path : "/\(path)"
		guard let url = components.url else {
			throw OntarioHansardAdapterError.invalidURL
		}
		return url
	}
}

private enum OntarioHansardHTTPClient {
	static func fetchData(from url: URL) async throws -> Data {
		var request = URLRequest(url: url, timeoutInterval: OntarioHansardConstants.requestTimeout)
		request.setValue("text/html, application/xhtml+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
		let (data, response) = try await NetworkService.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse,
		      OntarioHansardConstants.successStatusCodes.contains(httpResponse.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}
}

private struct OntarioHansardSession: Equatable {
	let parliamentNumber: Int
	let sessionNumber: Int
	let startDateKey: String
	let endDateKey: String?

	var indexPath: String {
		"/en/legislative-business/house-documents/parliament-\(parliamentNumber)/session-\(sessionNumber)"
	}

	func contains(dateKey: String) -> Bool {
		startDateKey <= dateKey && dateKey <= (endDateKey ?? OntarioHansardConstants.currentSessionOpenEnd)
	}

	func overlaps(startDateKey: String, endDateKey: String) -> Bool {
		self.startDateKey <= endDateKey && startDateKey <= (self.endDateKey ?? OntarioHansardConstants.currentSessionOpenEnd)
	}

	func directSource(for sittingDate: Date) throws -> OntarioHansardSource {
		let dateKey = OntarioHansardDateFormatter.key(from: sittingDate)
		return OntarioHansardSource(
			sittingDate: sittingDate,
			sittingDateKey: dateKey,
			parliamentNumber: parliamentNumber,
			sessionNumber: sessionNumber,
			htmlURL: try OntarioHansardURLBuilder.hansardURL(for: self, dateKey: dateKey),
			xmlURLs: []
		)
	}

	static func session(containing date: Date) -> OntarioHansardSession? {
		let dateKey = OntarioHansardDateFormatter.key(from: date)
		return knownSessions.first { $0.contains(dateKey: dateKey) }
	}

	static func sessions(overlapping startDate: Date, through endDate: Date) -> [OntarioHansardSession] {
		let startDateKey = OntarioHansardDateFormatter.key(from: startDate)
		let endDateKey = OntarioHansardDateFormatter.key(from: endDate)
		return knownSessions.filter { $0.overlaps(startDateKey: startDateKey, endDateKey: endDateKey) }
	}

	private static let knownSessions = [
		OntarioHansardSession(parliamentNumber: int("44"), sessionNumber: int("1"), startDateKey: "2025-04-14", endDateKey: nil),
		OntarioHansardSession(parliamentNumber: int("43"), sessionNumber: int("1"), startDateKey: "2022-08-08", endDateKey: "2025-01-28"),
		OntarioHansardSession(parliamentNumber: int("42"), sessionNumber: int("2"), startDateKey: "2021-10-04", endDateKey: "2022-05-03"),
		OntarioHansardSession(parliamentNumber: int("42"), sessionNumber: int("1"), startDateKey: "2018-07-11", endDateKey: "2021-09-12"),
		OntarioHansardSession(parliamentNumber: int("41"), sessionNumber: int("3"), startDateKey: "2018-03-19", endDateKey: "2018-05-08"),
		OntarioHansardSession(parliamentNumber: int("41"), sessionNumber: int("2"), startDateKey: "2016-09-12", endDateKey: "2018-03-15"),
		OntarioHansardSession(parliamentNumber: int("41"), sessionNumber: int("1"), startDateKey: "2014-07-02", endDateKey: "2016-09-08")
	]

	private static func int(_ value: String) -> Int {
		Int(value) ?? 0
	}
}

private struct OntarioHansardIndexPage {
	let session: OntarioHansardSession
	let html: String
}

private struct OntarioHansardSource: Hashable {
	let sittingDate: Date
	let sittingDateKey: String
	let parliamentNumber: Int
	let sessionNumber: Int
	let htmlURL: URL
	let xmlURLs: [URL]

	var xmlCandidateURLs: [URL] {
		(xmlURLs + htmlURL.derivedXMLCandidateURLs()).removingDuplicates()
	}
}

private enum OntarioHansardIndexParser {
	static func source(for sittingDate: Date, in html: String, session: OntarioHansardSession) -> OntarioHansardSource? {
		sources(in: html, session: session)
			.first { Calendar.utc.isDate($0.sittingDate, inSameDayAs: sittingDate) }
	}

	static func sittingDates(
		in html: String,
		session: OntarioHansardSession,
		from startDate: Date,
		through endDate: Date
	) -> [Date] {
		sources(in: html, session: session)
			.map(\.sittingDate)
			.filter { startDate <= $0 && $0 <= endDate }
			.removingDuplicates()
			.sorted()
	}

	private static func sources(in html: String, session: OntarioHansardSession) -> [OntarioHansardSource] {
		guard let document = try? HTML(html: html, encoding: .utf8) else { return [] }
		return document
			.xpath("//a[contains(@href, '/hansard') and time[@datetime]]")
			.compactMap { source(from: $0, session: session) }
			.removingDuplicates()
			.sorted { $0.sittingDate < $1.sittingDate }
	}

	private static func source(from link: XMLElement, session: OntarioHansardSession) -> OntarioHansardSource? {
		guard let href = link["href"],
		      let time = link.at_xpath(".//time[@datetime]"),
		      let dateTime = time["datetime"],
		      let dateKey = OntarioHansardDateFormatter.key(fromDateTime: dateTime),
		      let sittingDate = OntarioHansardDateFormatter.date(fromKey: dateKey),
		      let htmlURL = OntarioHansardURLBuilder.absoluteURL(from: href) else {
			return nil
		}
		return OntarioHansardSource(
			sittingDate: sittingDate,
			sittingDateKey: dateKey,
			parliamentNumber: session.parliamentNumber,
			sessionNumber: session.sessionNumber,
			htmlURL: htmlURL,
			xmlURLs: []
		)
	}
}

private struct OntarioHTMLHansardParser {
	private let scaffold: any HTMLHansardScaffold

	init(scaffold: any HTMLHansardScaffold) {
		self.scaffold = scaffold
	}

	func parse(html: String) throws -> [SubjectOfBusinessRecord] {
		guard let document = try? HTML(html: html, encoding: .utf8) else {
			throw OntarioHansardAdapterError.unparseableTranscript
		}
		let builder = OntarioHTMLSubjectBuilder(scaffold: scaffold)
		for element in transcriptElements(in: document) {
			builder.consume(element)
		}
		let subjects = builder.subjects()
		guard !subjects.isEmpty else {
			throw OntarioHansardAdapterError.unparseableTranscript
		}
		return subjects
	}

	private func transcriptElements(in document: HTMLDocument) -> [XMLElement] {
		let elements = Array(document.xpath(OntarioHansardConstants.transcriptXPath))
		return elements.isEmpty ? Array(document.xpath(OntarioHansardConstants.fallbackTranscriptXPath)) : elements
	}
}

private final class OntarioHTMLSubjectBuilder {
	private let scaffold: any HTMLHansardScaffold
	private var records: [SubjectOfBusinessRecord] = []
	private var currentTitle = "Debates"
	private var currentSubjectID = "debates"
	private var currentSpeeches: [SpeechMessageRecord] = []
	private var currentSpeaker: String?
	private var currentSpeakerMemberID: String?
	private var currentInterventionID: String?
	private var currentSpeechParagraphs: [String] = []
	private var subjectIndex = 0
	private var speechIndex = 0
	private var hasReachedProceedings = false

	init(scaffold: any HTMLHansardScaffold) {
		self.scaffold = scaffold
	}

	func consume(_ element: XMLElement) {
		switch element.tagName {
		case "h2", "h3":
			consumeHeading(element)
		case "p":
			consumeParagraph(element)
		default:
			break
		}
	}

	func subjects() -> [SubjectOfBusinessRecord] {
		flushSpeech()
		flushSubject()
		return records
	}

	private func consumeHeading(_ element: XMLElement) {
		let title = scaffold.normalizedText(element.text ?? "")
		guard title.count >= OntarioHansardConstants.minimumSubjectTitleCharacters else { return }
		hasReachedProceedings = true
		flushSpeech()
		flushSubject()
		subjectIndex += 1
		currentTitle = title
		currentSubjectID = element.firstSourceID ?? "subject-\(subjectIndex)-\(title.slug)"
	}

	private func consumeParagraph(_ element: XMLElement) {
		guard hasReachedProceedings, shouldConsumeParagraph(element) else { return }
		if let speechStart = speakerStart(from: element) {
			startSpeech(speechStart)
			return
		}
		appendToCurrentSpeech(scaffold.normalizedText(element.text ?? ""))
	}

	private func shouldConsumeParagraph(_ element: XMLElement) -> Bool {
		let className = element["class"] ?? ""
		return !className.contains("timeStamp") && !className.contains("procedure")
	}

	private func speakerStart(from element: XMLElement) -> OntarioSpeechStart? {
		let className = element["class"] ?? ""
		guard className.contains("speakerStart"),
		      let strong = element.at_xpath("./strong"),
		      let speakerText = strong.text else {
			return nil
		}
		let speaker = speakerText.strippingTrailingColon().strippingOntarioMPPTitle()
		let body = speechBody(in: element, speakerText: speakerText)
		return OntarioSpeechStart(
			speaker: speaker,
			speakerMemberID: nil,
			interventionID: element.firstSourceID,
			text: body
		)
	}

	private func speechBody(in element: XMLElement, speakerText: String) -> String {
		let paragraph = scaffold.normalizedText(element.text ?? "")
		guard paragraph.hasPrefix(scaffold.normalizedText(speakerText)) else {
			return paragraph.textAfterFirstColon()
		}
		return scaffold.normalizedText(String(paragraph.dropFirst(scaffold.normalizedText(speakerText).count)))
	}

	private func startSpeech(_ speechStart: OntarioSpeechStart) {
		flushSpeech()
		currentSpeaker = speechStart.speaker
		currentSpeakerMemberID = speechStart.speakerMemberID
		currentInterventionID = speechStart.interventionID
		currentSpeechParagraphs = speechStart.text.isEmpty ? [] : [speechStart.text]
	}

	private func appendToCurrentSpeech(_ text: String) {
		guard currentSpeaker != nil, !text.isEmpty else { return }
		currentSpeechParagraphs.append(text)
	}

	private func flushSpeech() {
		guard let currentSpeaker,
		      !currentSpeechParagraphs.isEmpty else {
			clearSpeech()
			return
		}
		let text = currentSpeechParagraphs.joined(separator: "\n\n")
		guard text.split(whereSeparator: \.isWhitespace).count >= OntarioHansardConstants.minimumSpeechWords else {
			clearSpeech()
			return
		}
		speechIndex += 1
		currentSpeeches.append(scaffold.makeSpeech(
			interventionID: speechID(for: currentSpeaker),
			speakerText: currentSpeaker,
			speakerMemberID: currentSpeakerMemberID,
			text: text
		))
		clearSpeech()
	}

	private func flushSubject() {
		guard !currentSpeeches.isEmpty else { return }
		records.append(scaffold.makeSubject(
			id: "on-subject-\(currentSubjectID)",
			title: currentTitle,
			speeches: currentSpeeches
		))
		currentSpeeches = []
	}

	private func speechID(for speaker: String) -> String {
		"on-\(currentInterventionID ?? "\(subjectIndex)-\(speechIndex)-\(speaker.slug)")"
	}

	private func clearSpeech() {
		currentSpeaker = nil
		currentSpeakerMemberID = nil
		currentInterventionID = nil
		currentSpeechParagraphs = []
	}
}

private struct OntarioSpeechStart {
	let speaker: String
	let speakerMemberID: String?
	let interventionID: String?
	let text: String
}

private enum OntarioXMLHansardParser {
	static func parse(data: Data, source: OntarioHansardSource) throws -> [SubjectOfBusinessRecord] {
		let parser = XMLParser(data: data)
		let delegate = OntarioXMLParserDelegate(source: source)
		parser.delegate = delegate
		guard parser.parse(), !delegate.subjects.isEmpty else {
			throw OntarioHansardAdapterError.unparseableTranscript
		}
		return delegate.subjects
	}
}

private final class OntarioXMLParserDelegate: NSObject, XMLParserDelegate {
	private(set) var subjects: [SubjectOfBusinessRecord] = []
	private var currentElement = ""
	private var currentSubjectTitle = "Debates"
	private var currentSpeeches: [SpeechMessageRecord] = []
	private var currentSpeaker = ""
	private var currentText = ""
	private var currentInterventionID = ""
	private var currentSpeakerMemberID: String?
	private var subjectIndex = 0
	private var speechIndex = 0
	private let source: OntarioHansardSource
	private let scaffold = OntarioXMLScaffold()

	init(source: OntarioHansardSource) {
		self.source = source
	}

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName qName: String?,
		attributes attributeDict: [String: String] = [:]
	) {
		currentElement = elementName.lowercased()
		if isSubjectElement(currentElement) {
			startSubject(attributes: attributeDict)
		}
		if isSpeechElement(currentElement) {
			startSpeech(attributes: attributeDict)
		}
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		if isSpeakerElement(currentElement) {
			currentSpeaker += string
		}
		if isSpeechTextElement(currentElement) {
			currentText += string
		}
		if isSubjectTitleElement(currentElement) {
			currentSubjectTitle += string
		}
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
		let name = elementName.lowercased()
		if isSpeechElement(name) {
			flushSpeech()
		}
		if isSubjectElement(name) {
			flushSubject()
		}
	}

	private func startSubject(attributes: [String: String]) {
		flushSubject()
		subjectIndex += 1
		currentSubjectTitle = attributes["title"] ?? attributes["name"] ?? "Debates"
	}

	private func startSpeech(attributes: [String: String]) {
		currentSpeaker = attributes["speaker"] ?? attributes["speakerName"] ?? ""
		currentText = ""
		currentInterventionID = attributes["id"] ?? attributes["interventionID"] ?? ""
		currentSpeakerMemberID = attributes["memberId"] ?? attributes["memberID"] ?? attributes["personId"]
	}

	private func flushSpeech() {
		let speaker = scaffold.normalizedText(currentSpeaker).strippingOntarioMPPTitle()
		let text = scaffold.normalizedText(currentText)
		guard !speaker.isEmpty, !text.isEmpty else { return }
		speechIndex += 1
		currentSpeeches.append(scaffold.makeSpeech(
			interventionID: speechID(for: speaker),
			speakerText: speaker,
			speakerMemberID: currentSpeakerMemberID,
			text: text
		))
		currentSpeaker = ""
		currentText = ""
		currentInterventionID = ""
		currentSpeakerMemberID = nil
	}

	private func flushSubject() {
		guard !currentSpeeches.isEmpty else { return }
		let title = scaffold.normalizedText(currentSubjectTitle)
		subjects.append(scaffold.makeSubject(
			id: "on-xml-\(source.sittingDateKey)-subject-\(subjectIndex)-\(title.slug)",
			title: title.isEmpty ? "Debates" : title,
			speeches: currentSpeeches
		))
		currentSpeeches = []
		currentSubjectTitle = "Debates"
	}

	private func speechID(for speaker: String) -> String {
		let sourceID = currentInterventionID.isEmpty ? "\(subjectIndex)-\(speechIndex)-\(speaker.slug)" : currentInterventionID
		return "on-xml-\(source.sittingDateKey)-\(sourceID)"
	}

	private func isSubjectElement(_ name: String) -> Bool {
		name == "subject" || name == "section" || name == "business" || name == "debate"
	}

	private func isSpeechElement(_ name: String) -> Bool {
		name == "speech" || name == "intervention" || name == "statement"
	}

	private func isSpeakerElement(_ name: String) -> Bool {
		name == "speaker" || name == "speakername" || name == "member"
	}

	private func isSpeechTextElement(_ name: String) -> Bool {
		name == "text" || name == "p" || name == "para" || name == "paragraph" || name == "content" || name == "body"
	}

	private func isSubjectTitleElement(_ name: String) -> Bool {
		name == "title" || name == "heading"
	}
}

private struct OntarioXMLScaffold: HTMLHansardScaffold {
	let jurisdiction: Jurisdiction = .ontario
}

private enum OntarioHansardTextDecoder {
	static func string(from data: Data) throws -> String {
		if let text = String(data: data, encoding: .utf8) {
			return text
		}
		if let text = String(data: data, encoding: .windowsCP1252) {
			return text
		}
		throw OntarioHansardAdapterError.unparseableTranscript
	}
}

private enum OntarioHansardDateFormatter {
	static let url: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = .utc
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = .utc
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	static func key(from date: Date) -> String {
		url.string(from: date)
	}

	static func key(fromDateTime value: String) -> String? {
		guard value.count >= OntarioHansardConstants.dateKeyLength else { return nil }
		let key = String(value.prefix(OntarioHansardConstants.dateKeyLength))
		return date(fromKey: key).map { _ in key }
	}

	static func date(fromKey value: String) -> Date? {
		url.date(from: value)
	}
}

private extension XMLElement {
	var firstSourceID: String? {
		Array(xpath(".//span[starts-with(@id, 'P')]")).first?["id"]
			?? Array(xpath(".//span[starts-with(@id, 'para')]")).first?["id"]
	}
}

private extension String {
	func strippingTrailingColon() -> String {
		trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func strippingOntarioMPPTitle() -> String {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.hasPrefix("MPP ") ? String(trimmed.dropFirst("MPP ".count)) : trimmed
	}

	func textAfterFirstColon() -> String {
		guard let colon = firstIndex(of: ":") else { return self }
		return String(self[index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var slug: String {
		let allowed = CharacterSet.alphanumerics
		let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
		return String(scalars)
			.lowercased()
			.split(separator: "-")
			.joined(separator: "-")
	}
}

private extension URL {
	func derivedXMLCandidateURLs() -> [URL] {
		[
			appendingPathExtension("xml"),
			withQueryItem(name: "output", value: "xml"),
			withQueryItem(name: "format", value: "xml")
		].compactMap(\.self)
	}

	func withQueryItem(name: String, value: String) -> URL? {
		guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
		var queryItems = components.queryItems ?? []
		queryItems.append(URLQueryItem(name: name, value: value))
		components.queryItems = queryItems
		return components.url
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
