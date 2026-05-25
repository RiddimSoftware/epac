//
//  SaskatchewanHansardAdapter.swift
//  epac
//

import Foundation
import Kanna

@MainActor
struct SaskatchewanHansardAdapter: HansardRepository, HTMLHansardScaffold {
	typealias FetchData = @Sendable (URL) async throws -> Data
	typealias Sleep = @Sendable (Duration) async throws -> Void
	typealias PersistTranscript = @MainActor @Sendable (HansardTranscript) async throws -> Void

	let jurisdiction: Jurisdiction = .saskatchewan

	private let fetchData: FetchData
	private let sleep: Sleep
	private let persistTranscript: PersistTranscript

	init(
		fetchData: @escaping FetchData = SaskatchewanHansardHTTPClient.fetchData,
		sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
		persistTranscript: @escaping PersistTranscript = { _ in throw SaskatchewanHansardAdapterError.persistenceNotConfigured }
	) {
		self.fetchData = fetchData
		self.sleep = sleep
		self.persistTranscript = persistTranscript
	}

	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		try requireSupported(jurisdiction)
		let source = try await transcriptSource(for: sittingDate)
		if let xmlTranscript = try await fetchXMLTranscript(from: source, sittingDate: sittingDate) {
			return xmlTranscript
		}
		return try await fetchHTMLTranscript(from: source, sittingDate: sittingDate)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
		try requireSupported(jurisdiction)
		guard startDate <= endDate else { return [] }
		let index = try await fetchArchiveIndex(from: startDate, through: endDate)
		return SaskatchewanHansardIndexParser.sittingDates(in: index, from: startDate, through: endDate)
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		try requireSupported(transcript.jurisdiction)
		try await persistTranscript(transcript)
	}

	private func transcriptSource(for sittingDate: Date) async throws -> SaskatchewanHansardSource {
		let index = try await fetchArchiveIndex(from: sittingDate, through: sittingDate)
		guard let source = SaskatchewanHansardIndexParser.source(for: sittingDate, in: index) else {
			throw SaskatchewanHansardAdapterError.transcriptNotFound(sittingDate)
		}
		return source
	}

	private func fetchArchiveIndex(from startDate: Date, through endDate: Date) async throws -> String {
		let data = try await fetchData(SaskatchewanHansardURLBuilder.archiveURL(from: startDate, through: endDate))
		return try SaskatchewanHansardTextDecoder.string(from: data)
	}

	private func fetchXMLTranscript(
		from source: SaskatchewanHansardSource,
		sittingDate: Date
	) async throws -> HansardTranscript? {
		for url in source.xmlCandidateURLs {
			try await sleep(SaskatchewanHansardConstants.requestSpacing)
			if let transcript = try await probeXMLTranscript(url: url, source: source, sittingDate: sittingDate) {
				return transcript
			}
		}
		return nil
	}

	private func probeXMLTranscript(
		url: URL,
		source: SaskatchewanHansardSource,
		sittingDate: Date
	) async throws -> HansardTranscript? {
		do {
			let data = try await fetchData(url)
			let subjects = try SaskatchewanXMLHansardParser.parse(data: data)
			return makeTranscript(
				sittingDate: sittingDate,
				legislatureNumber: source.legislatureNumber,
				sourceURL: url,
				subjects: subjects
			)
		} catch SaskatchewanHansardAdapterError.unparseableTranscript {
			throw SaskatchewanHansardAdapterError.unparseableTranscript
		} catch {
			return nil
		}
	}

	private func fetchHTMLTranscript(
		from source: SaskatchewanHansardSource,
		sittingDate: Date
	) async throws -> HansardTranscript {
		try await sleep(SaskatchewanHansardConstants.requestSpacing)
		let data = try await fetchData(source.htmlURL)
		let html = try SaskatchewanHansardTextDecoder.string(from: data)
		let subjects = try SaskatchewanHTMLHansardParser(scaffold: self).parse(html: html)
		return makeTranscript(
			sittingDate: sittingDate,
			legislatureNumber: source.legislatureNumber,
			sourceURL: source.htmlURL,
			subjects: subjects
		)
	}

	private func requireSupported(_ jurisdiction: Jurisdiction) throws {
		guard jurisdiction == .saskatchewan else {
			throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
		}
	}
}

enum SaskatchewanHansardAdapterError: Error, Equatable {
	case invalidArchiveURL
	case transcriptNotFound(Date)
	case unparseableTranscript
	case persistenceNotConfigured
}

private enum SaskatchewanHansardConstants {
	static let legislativeAssemblyCommitteeCode = "280140000"
	static let debatesDocumentTypeCode = "280140005"
	static let requestTimeout: TimeInterval = 20
	static let successStatusLowerBound = 200
	static let successStatusUpperBound = 300
	static let requestSpacing: Duration = .seconds(1)
	static let minimumSubjectTitleCharacters = 2
	static let maximumSpeakerPrefixCharacters = 80
	static let maximumSpeakerWordCount = 5
	static let minimumSpeechWords = 2
	static let datePathLength = 8
	static let expectedLinkCaptureCount = 5

	static var successStatusCodes: Range<Int> {
		successStatusLowerBound..<successStatusUpperBound
	}
}

private enum SaskatchewanHansardURLBuilder {
	static func archiveURL(from startDate: Date, through endDate: Date) throws -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.legassembly.sk.ca"
		components.path = "/legislative-business/archive/"
		components.queryItems = [
			URLQueryItem(name: "Start", value: SaskatchewanHansardDateFormatter.archive.string(from: startDate)),
			URLQueryItem(name: "End", value: SaskatchewanHansardDateFormatter.archive.string(from: endDate)),
			URLQueryItem(name: "Committee", value: SaskatchewanHansardConstants.legislativeAssemblyCommitteeCode),
			URLQueryItem(name: "Type", value: SaskatchewanHansardConstants.debatesDocumentTypeCode)
		]
		guard let url = components.url else {
			throw SaskatchewanHansardAdapterError.invalidArchiveURL
		}
		return url
	}
}

private enum SaskatchewanHansardHTTPClient {
	static func fetchData(from url: URL) async throws -> Data {
		var request = URLRequest(url: url, timeoutInterval: SaskatchewanHansardConstants.requestTimeout)
		request.setValue("text/html, application/xhtml+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
		let (data, response) = try await NetworkService.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse,
		      SaskatchewanHansardConstants.successStatusCodes.contains(httpResponse.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}
}

private struct SaskatchewanHansardSource: Equatable {
	let sittingDate: Date
	let legislatureNumber: Int
	let sessionNumber: Int
	let htmlURL: URL
	let xmlURLs: [URL]

	var xmlCandidateURLs: [URL] {
		(xmlURLs + htmlURL.derivedXMLCandidateURLs()).removingDuplicates()
	}
}

private enum SaskatchewanHansardIndexParser {
	private static let debatesLinkPattern = #"https://docs\.legassembly\.sk\.ca/legdocs/(?:Assembly/Debates|Legislative%20Assembly/Hansard)/([0-9]+)L([0-9]+)S/([0-9]{8})Debates(?:-?HTML)?\.(htm|xml)"#

	static func source(for sittingDate: Date, in html: String) -> SaskatchewanHansardSource? {
		sources(in: html)
			.first { Calendar.utc.isDate($0.sittingDate, inSameDayAs: sittingDate) }
	}

	static func sittingDates(in html: String, from startDate: Date, through endDate: Date) -> [Date] {
		sources(in: html)
			.map(\.sittingDate)
			.filter { startDate <= $0 && $0 <= endDate }
			.removingDuplicates()
			.sorted()
	}

	private static func sources(in html: String) -> [SaskatchewanHansardSource] {
		let links = debateLinks(in: html)
		let grouped = Dictionary(grouping: links, by: \.sittingDate)
		return grouped.values.compactMap(source(from:)).sorted { $0.sittingDate < $1.sittingDate }
	}

	private static func source(from links: [DebateLink]) -> SaskatchewanHansardSource? {
		guard let first = links.first,
		      let htmlURL = links.first(where: { $0.kind == .html })?.url else {
			return nil
		}
		return SaskatchewanHansardSource(
			sittingDate: first.sittingDate,
			legislatureNumber: first.legislatureNumber,
			sessionNumber: first.sessionNumber,
			htmlURL: htmlURL,
			xmlURLs: links.filter { $0.kind == .xml }.map(\.url)
		)
	}

	private static func debateLinks(in html: String) -> [DebateLink] {
		guard let regex = try? NSRegularExpression(pattern: debatesLinkPattern) else { return [] }
		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		return regex.matches(in: html, range: range).compactMap { DebateLink(match: $0, html: html) }
	}
}

private struct DebateLink: Equatable {
	enum Kind {
		case html
		case xml
	}

	let url: URL
	let legislatureNumber: Int
	let sessionNumber: Int
	let sittingDate: Date
	let kind: Kind

	init?(match: NSTextCheckingResult, html: String) {
		guard match.numberOfRanges == SaskatchewanHansardConstants.expectedLinkCaptureCount,
		      let url = URL(string: html.capture(match, at: MatchCapture.whole)),
		      let legislature = Int(html.capture(match, at: MatchCapture.legislature)),
		      let session = Int(html.capture(match, at: MatchCapture.session)),
		      let date = SaskatchewanHansardDateFormatter.date(fromPath: html.capture(match, at: MatchCapture.date)) else {
			return nil
		}
		self.url = url
		legislatureNumber = legislature
		sessionNumber = session
		sittingDate = date
		kind = html.capture(match, at: MatchCapture.fileExtension) == "xml" ? .xml : .html
	}
}

private enum MatchCapture {
	static let whole = 0
	static let legislature = 1
	static let session = 2
	static let date = 3
	static let fileExtension = 4
}

private struct SaskatchewanHTMLHansardParser {
	private let scaffold: any HTMLHansardScaffold

	init(scaffold: any HTMLHansardScaffold) {
		self.scaffold = scaffold
	}

	func parse(html: String) throws -> [SubjectOfBusinessRecord] {
		guard let document = try? HTML(html: html, encoding: .windowsCP1252) else {
			throw SaskatchewanHansardAdapterError.unparseableTranscript
		}
		let builder = SaskatchewanHTMLSubjectBuilder(scaffold: scaffold)
		for element in document.xpath("//h1|//h2|//p") {
			builder.consume(element)
		}
		let subjects = builder.subjects()
		guard !subjects.isEmpty else {
			throw SaskatchewanHansardAdapterError.unparseableTranscript
		}
		return subjects
	}
}

private final class SaskatchewanHTMLSubjectBuilder {
	private let scaffold: any HTMLHansardScaffold
	private var records: [SubjectOfBusinessRecord] = []
	private var currentTitle = "Debates"
	private var currentSpeeches: [SpeechMessageRecord] = []
	private var currentSpeaker: String?
	private var currentSpeechParagraphs: [String] = []
	private var subjectIndex = 0
	private var speechIndex = 0
	private var hasReachedProceedings = false

	init(scaffold: any HTMLHansardScaffold) {
		self.scaffold = scaffold
	}

	func consume(_ element: XMLElement) {
		guard shouldConsume(element) else { return }
		if element.tagName == "h1" || element.tagName == "h2" {
			consumeHeading(element.text ?? "")
			return
		}
		consumeParagraph(element.text ?? "")
	}

	func subjects() -> [SubjectOfBusinessRecord] {
		flushSpeech()
		flushSubject()
		return records
	}

	private func shouldConsume(_ element: XMLElement) -> Bool {
		let className = element["class"] ?? ""
		return !className.contains("MsoToc")
	}

	private func consumeHeading(_ text: String) {
		let title = scaffold.normalizedText(text)
		guard title.count >= SaskatchewanHansardConstants.minimumSubjectTitleCharacters else { return }
		hasReachedProceedings = true
		flushSpeech()
		flushSubject()
		currentTitle = title
		subjectIndex += 1
	}

	private func consumeParagraph(_ text: String) {
		guard hasReachedProceedings else { return }
		let normalized = scaffold.normalizedText(text)
		guard !normalized.isEmpty, !isTimestamp(normalized) else { return }
		if let speechStart = SaskatchewanSpeakerLineParser.parse(normalized) {
			startSpeech(speechStart)
			return
		}
		appendToCurrentSpeech(normalized)
	}

	private func startSpeech(_ speechStart: SaskatchewanSpeechStart) {
		flushSpeech()
		currentSpeaker = speechStart.speaker
		currentSpeechParagraphs = speechStart.text.isEmpty ? [] : [speechStart.text]
	}

	private func appendToCurrentSpeech(_ text: String) {
		guard currentSpeaker != nil else { return }
		currentSpeechParagraphs.append(text)
	}

	private func flushSpeech() {
		guard let currentSpeaker,
		      !currentSpeechParagraphs.isEmpty else {
			currentSpeaker = nil
			currentSpeechParagraphs = []
			return
		}
		let text = currentSpeechParagraphs.joined(separator: "\n\n")
		guard text.split(whereSeparator: \.isWhitespace).count >= SaskatchewanHansardConstants.minimumSpeechWords else { return }
		speechIndex += 1
		currentSpeeches.append(scaffold.makeSpeech(
			interventionID: "sk-\(subjectIndex)-\(speechIndex)-\(currentSpeaker.slug)",
			speakerText: currentSpeaker,
			speakerMemberID: nil,
			text: text
		))
		self.currentSpeaker = nil
		currentSpeechParagraphs = []
	}

	private func flushSubject() {
		guard !currentSpeeches.isEmpty else { return }
		records.append(scaffold.makeSubject(
			id: "sk-subject-\(subjectIndex)-\(currentTitle.slug)",
			title: currentTitle,
			speeches: currentSpeeches
		))
		currentSpeeches = []
	}

	private func isTimestamp(_ text: String) -> Bool {
		text.hasPrefix("[") && text.hasSuffix("]")
	}
}

private struct SaskatchewanSpeechStart {
	let speaker: String
	let text: String
}

private enum SaskatchewanSpeakerLineParser {
	private static let knownPrefixes = [
		"Hon.",
		"Mr.",
		"Ms.",
		"Mrs.",
		"Speaker",
		"Deputy Speaker",
		"Hon. Members",
		"Some Hon. Members",
		"An Hon. Member",
		"The Speaker"
	]

	static func parse(_ text: String) -> SaskatchewanSpeechStart? {
		guard let colonRange = text.range(of: ":") else { return nil }
		let prefix = String(text[..<colonRange.lowerBound])
		guard isSpeaker(prefix) else { return nil }
		let speech = String(text[colonRange.upperBound...]).trimmingSpeechLead()
		return SaskatchewanSpeechStart(speaker: prefix, text: speech)
	}

	private static func isSpeaker(_ value: String) -> Bool {
		let speaker = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard speaker.count <= SaskatchewanHansardConstants.maximumSpeakerPrefixCharacters,
		      speaker.split(whereSeparator: \.isWhitespace).count <= SaskatchewanHansardConstants.maximumSpeakerWordCount else {
			return false
		}
		return hasKnownPrefix(speaker) || isNameLikeSpeaker(speaker)
	}

	private static func hasKnownPrefix(_ speaker: String) -> Bool {
		knownPrefixes.contains { speaker == $0 || speaker.hasPrefix("\($0) ") }
	}

	private static func isNameLikeSpeaker(_ speaker: String) -> Bool {
		let words = speaker.split(whereSeparator: \.isWhitespace)
		guard words.count > 1 else { return false }
		return words.allSatisfy { word in
			word.first.map { $0.isUppercase } == true
		}
	}
}

private enum SaskatchewanXMLHansardParser {
	static func parse(data: Data) throws -> [SubjectOfBusinessRecord] {
		let parser = XMLParser(data: data)
		let delegate = SaskatchewanXMLParserDelegate()
		parser.delegate = delegate
		guard parser.parse(), !delegate.subjects.isEmpty else {
			throw SaskatchewanHansardAdapterError.unparseableTranscript
		}
		return delegate.subjects
	}
}

private final class SaskatchewanXMLParserDelegate: NSObject, XMLParserDelegate {
	private(set) var subjects: [SubjectOfBusinessRecord] = []
	private var currentElement = ""
	private var currentSubjectTitle = "Debates"
	private var currentSpeeches: [SpeechMessageRecord] = []
	private var currentSpeaker = ""
	private var currentText = ""
	private var subjectIndex = 0
	private var speechIndex = 0
	private let scaffold = SaskatchewanXMLScaffold()

	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
		currentElement = elementName.lowercased()
		if isSubjectElement(currentElement) {
			flushSubject()
			subjectIndex += 1
			currentSubjectTitle = attributeDict["title"] ?? "Debates"
		}
		if isSpeechElement(currentElement) {
			currentSpeaker = attributeDict["speaker"] ?? ""
			currentText = ""
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

	private func flushSpeech() {
		let speaker = scaffold.normalizedText(currentSpeaker)
		let text = scaffold.normalizedText(currentText)
		guard !speaker.isEmpty, !text.isEmpty else { return }
		speechIndex += 1
		currentSpeeches.append(scaffold.makeSpeech(
			interventionID: "sk-xml-\(subjectIndex)-\(speechIndex)-\(speaker.slug)",
			speakerText: speaker,
			speakerMemberID: nil,
			text: text
		))
		currentSpeaker = ""
		currentText = ""
	}

	private func flushSubject() {
		guard !currentSpeeches.isEmpty else { return }
		subjects.append(scaffold.makeSubject(
			id: "sk-xml-subject-\(subjectIndex)-\(currentSubjectTitle.slug)",
			title: currentSubjectTitle,
			speeches: currentSpeeches
		))
		currentSpeeches = []
		currentSubjectTitle = "Debates"
	}

	private func isSubjectElement(_ name: String) -> Bool {
		name == "subject" || name == "section" || name == "business"
	}

	private func isSpeechElement(_ name: String) -> Bool {
		name == "speech" || name == "intervention" || name == "statement"
	}

	private func isSpeakerElement(_ name: String) -> Bool {
		name == "speaker" || name == "speakername"
	}

	private func isSpeechTextElement(_ name: String) -> Bool {
		name == "text" || name == "p" || name == "para" || name == "paragraph"
	}

	private func isSubjectTitleElement(_ name: String) -> Bool {
		name == "title" || name == "heading"
	}
}

private struct SaskatchewanXMLScaffold: HTMLHansardScaffold {
	let jurisdiction: Jurisdiction = .saskatchewan
}

private enum SaskatchewanHansardTextDecoder {
	static func string(from data: Data) throws -> String {
		if let text = String(data: data, encoding: .utf8) {
			return text
		}
		if let text = String(data: data, encoding: .windowsCP1252) {
			return text
		}
		throw SaskatchewanHansardAdapterError.unparseableTranscript
	}
}

private enum SaskatchewanHansardDateFormatter {
	static let archive: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = .utc
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = .utc
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	static func date(fromPath value: String) -> Date? {
		guard value.count == SaskatchewanHansardConstants.datePathLength,
		      let year = Int(value.prefix(DatePathIndex.yearEnd)),
		      let month = Int(value.dropFirst(DatePathIndex.yearEnd).prefix(DatePathIndex.monthLength)),
		      let day = Int(value.suffix(DatePathIndex.dayLength)) else {
			return nil
		}
		return Calendar.utc.date(from: DateComponents(timeZone: .utc, year: year, month: month, day: day))
	}
}

private enum DatePathIndex {
	static let yearEnd = 4
	static let monthLength = 2
	static let dayLength = 2
}

private extension String {
	func capture(_ match: NSTextCheckingResult, at index: Int) -> String {
		guard let range = Range(match.range(at: index), in: self) else { return "" }
		return String(self[range])
	}

	func trimmingSpeechLead() -> String {
		trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: "—–- "))
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
}

private extension URL {
	func derivedXMLCandidateURLs() -> [URL] {
		[
			replacingLastPathComponentSuffix("-HTML.htm", with: ".xml"),
			replacingLastPathComponentSuffix("HTML.htm", with: ".xml"),
			replacingLastPathComponentSuffix("-HTML.htm", with: "-XML.xml"),
			replacingLastPathComponentSuffix("HTML.htm", with: "XML.xml")
		].compactMap(\.self)
	}

	func replacingLastPathComponentSuffix(_ suffix: String, with replacement: String) -> URL? {
		let path = absoluteString
		guard path.hasSuffix(suffix) else { return nil }
		return URL(string: String(path.dropLast(suffix.count)) + replacement)
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
