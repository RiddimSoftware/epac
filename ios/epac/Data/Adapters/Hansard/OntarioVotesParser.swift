//
//  OntarioVotesParser.swift
//  epac
//

import Foundation

enum OntarioVotesParserError: Error {
	case invalidFormat
	case missingSittingDate
}

struct OntarioVotesParser {
	func parse(document: String, sittingDate: Date) throws -> [RecordedVote] {
		let trimmed = document.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("<") && !trimmed.localizedCaseInsensitiveContains("<!doctype html") {
			let votes = try parseXML(document, sittingDate: sittingDate)
			if !votes.isEmpty {
				return votes
			}
		}
		return try parseHTML(document, sittingDate: sittingDate)
	}

	private func parseXML(_ xml: String, sittingDate: Date) throws -> [RecordedVote] {
		guard let data = xml.data(using: .utf8) else {
			throw OntarioVotesParserError.invalidFormat
		}
		let delegate = OntarioVotesXMLDelegate(sittingDate: sittingDate)
		let parser = XMLParser(data: data)
		parser.delegate = delegate
		guard parser.parse() else {
			throw parser.parserError ?? OntarioVotesParserError.invalidFormat
		}
		return delegate.votes
	}

	private func parseHTML(_ html: String, sittingDate: Date) throws -> [RecordedVote] {
		let events = OntarioHTMLVotesExtractor.events(in: html)
		guard !events.isEmpty else {
			throw OntarioVotesParserError.invalidFormat
		}
		return OntarioVoteFactory.makeVotes(
			from: events,
			sittingDate: sittingDate,
			metadata: OntarioHTMLVotesExtractor.metadata(in: html)
		)
	}
}

private struct OntarioVoteEvent {
	let sourceID: String
	let texts: [String]
	let divisions: [OntarioDivisionSection]
}

private struct OntarioDivisionSection {
	let ballot: String
	let declaredCount: Int?
	let memberNames: [String]
}

private struct OntarioVotesMetadata {
	let parliament: Int
	let session: Int

	static let fallback = OntarioVotesMetadata(parliament: Constants.currentParliament, session: Constants.currentSession)
}

private struct OntarioVoteFactory {
	static func makeVotes(
		from events: [OntarioVoteEvent],
		sittingDate: Date,
		metadata: OntarioVotesMetadata
	) -> [RecordedVote] {
		events.enumerated().compactMap { offset, event in
			makeVote(event: event, index: offset, sittingDate: sittingDate, metadata: metadata)
		}
	}

	private static func makeVote(
		event: OntarioVoteEvent,
		index: Int,
		sittingDate: Date,
		metadata: OntarioVotesMetadata
	) -> RecordedVote? {
		guard !event.divisions.isEmpty else { return nil }
		let description = description(from: event.texts)
		let voteID = OntarioStableIdentifier.voteID(sourceID: event.sourceID, date: sittingDate, index: index)
		let vote = RecordedVote(
			voteID: voteID,
			parliament: metadata.parliament,
			session: metadata.session,
			number: index + Constants.oneBasedOffset,
			date: sittingDate,
			descriptionEn: description,
			billNumberCode: billNumber(in: description),
			yea: count(for: Constants.ayeBallot, in: event.divisions),
			nay: count(for: Constants.nayBallot, in: event.divisions),
			paired: count(for: Constants.pairedBallot, in: event.divisions),
			resultEn: outcome(from: event.texts),
			jurisdiction: Jurisdiction.ontario.rawValue
		)
		appendMemberVotes(to: vote, voteID: voteID, divisions: event.divisions)
		return vote
	}

	private static func appendMemberVotes(
		to vote: RecordedVote,
		voteID: Int,
		divisions: [OntarioDivisionSection]
	) {
		for division in divisions {
			for memberName in division.memberNames {
				let memberVote = MemberVote(
					voteID: voteID,
					memberID: OntarioStableIdentifier.memberID(name: memberName),
					recordedVote: division.ballot,
					jurisdiction: Jurisdiction.ontario.rawValue
				)
				vote.memberVotes.append(memberVote)
				memberVote.vote = vote
			}
		}
	}

	private static func count(for ballot: String, in divisions: [OntarioDivisionSection]) -> Int {
		divisions
			.filter { $0.ballot == ballot }
			.reduce(Constants.zero) { total, section in
				total + (section.declaredCount ?? section.memberNames.count)
			}
	}

	private static func description(from texts: [String]) -> String {
		texts.first { !isOutcomeText($0) } ?? ""
	}

	private static func outcome(from texts: [String]) -> String {
		guard let text = texts.first(where: isOutcomeText) else { return "" }
		if text.localizedCaseInsensitiveContains(Constants.carriedText) {
			return Constants.carriedText
		}
		if text.localizedCaseInsensitiveContains(Constants.lostText) {
			return Constants.lostText
		}
		return text
	}

	private static func isOutcomeText(_ text: String) -> Bool {
		text.localizedCaseInsensitiveContains(Constants.divisionText)
			|| text.localizedCaseInsensitiveContains(Constants.carriedText)
			|| text.localizedCaseInsensitiveContains(Constants.lostText)
	}

	private static func billNumber(in text: String) -> String {
		guard let match = text.firstMatch(of: Constants.billPattern) else { return "" }
		return String(text[match.range])
	}
}

private struct OntarioHTMLVotesExtractor {
	static func metadata(in html: String) -> OntarioVotesMetadata {
		let text = OntarioText.normalize(OntarioText.strippingTags(from: html))
		return metadata(from: text, pattern: Constants.parliamentSessionLabelPattern)
			?? metadata(from: text, pattern: Constants.parliamentSessionOrdinalPattern)
			?? .fallback
	}

	static func events(in html: String) -> [OntarioVoteEvent] {
		let fragments = html.matches(of: Constants.eventPattern).map { String($0.1) }
		let grouped = fragments.reduce(into: [String: OntarioVoteEventBuilder]()) { partial, fragment in
			append(fragment: fragment, to: &partial)
		}
		return orderedIDs(in: fragments).compactMap { grouped[$0]?.event }
	}

	private static func append(fragment: String, to grouped: inout [String: OntarioVoteEventBuilder]) {
		guard let sourceID = sourceID(in: fragment) else { return }
		var builder = grouped[sourceID, default: OntarioVoteEventBuilder(sourceID: sourceID)]
		builder.texts.append(contentsOf: englishTexts(in: fragment))
		builder.divisions.append(contentsOf: divisions(in: fragment))
		grouped[sourceID] = builder
	}

	private static func orderedIDs(in fragments: [String]) -> [String] {
		fragments.compactMap(sourceID).removingDuplicates()
	}

	private static func sourceID(in fragment: String) -> String? {
		guard let match = fragment.firstMatch(of: Constants.tableIDPattern) else { return nil }
		return String(match.1)
	}

	private static func englishTexts(in fragment: String) -> [String] {
		fragment.matches(of: Constants.englishCellPattern).compactMap { match in
			let text = OntarioText.normalize(OntarioText.strippingTags(from: String(match.1)))
			return text.isEmpty ? nil : text
		}
	}

	private static func divisions(in fragment: String) -> [OntarioDivisionSection] {
		let headers = fragment.matches(of: Constants.divisionHeaderPattern)
		return headers.enumerated().compactMap { offset, match in
			division(from: match, offset: offset, headers: headers, fragment: fragment)
		}
	}

	private static func division(
		from match: Regex<(Substring, Substring, Substring)>.Match,
		offset: Int,
		headers: [Regex<(Substring, Substring, Substring)>.Match],
		fragment: String
	) -> OntarioDivisionSection? {
		guard let ballot = ballot(from: String(match.1)) else { return nil }
		let body = body(after: match, offset: offset, headers: headers, fragment: fragment)
		let count = Int(match.2)
		let names = memberNames(in: body)
		return OntarioDivisionSection(ballot: ballot, declaredCount: count, memberNames: names)
	}

	private static func body(
		after match: Regex<(Substring, Substring, Substring)>.Match,
		offset: Int,
		headers: [Regex<(Substring, Substring, Substring)>.Match],
		fragment: String
	) -> String {
		let start = match.range.upperBound
		let end = nextHeaderStart(after: offset, headers: headers) ?? fragment.endIndex
		return String(fragment[start..<end])
	}

	private static func nextHeaderStart(
		after offset: Int,
		headers: [Regex<(Substring, Substring, Substring)>.Match]
	) -> String.Index? {
		let nextOffset = offset + Constants.oneBasedOffset
		guard nextOffset < headers.count else { return nil }
		return headers[nextOffset].range.lowerBound
	}

	private static func memberNames(in html: String) -> [String] {
		html.matches(of: Constants.tableCellPattern).compactMap { match in
			let text = OntarioText.normalize(OntarioText.strippingTags(from: String(match.1)))
			return text.isEmpty ? nil : text
		}
	}

	private static func metadata(
		from text: String,
		pattern: Regex<(Substring, Substring, Substring)>
	) -> OntarioVotesMetadata? {
		guard let match = text.firstMatch(of: pattern),
		      let parliament = Int(match.1),
		      let session = Int(match.2) else {
			return nil
		}
		return OntarioVotesMetadata(parliament: parliament, session: session)
	}

	private static func ballot(from header: String) -> String? {
		let normalized = OntarioText.normalize(OntarioText.strippingTags(from: header)).lowercased()
		if normalized.contains(Constants.ayesLower) || normalized.contains(Constants.yeasLower) {
			return Constants.ayeBallot
		}
		if normalized.contains(Constants.naysLower) {
			return Constants.nayBallot
		}
		if normalized.contains(Constants.pairedLower) || normalized.contains(Constants.abstainedLower) {
			return Constants.pairedBallot
		}
		return nil
	}
}

private struct OntarioVoteEventBuilder {
	let sourceID: String
	var texts: [String] = []
	var divisions: [OntarioDivisionSection] = []

	var event: OntarioVoteEvent {
		OntarioVoteEvent(sourceID: sourceID, texts: texts, divisions: divisions)
	}
}

private final class OntarioVotesXMLDelegate: NSObject, XMLParserDelegate {
	private let sittingDate: Date
	private var currentText = ""
	private var currentVote: OntarioXMLVoteBuilder?
	private var currentBallot: String?

	var votes: [RecordedVote] = []

	init(sittingDate: Date) {
		self.sittingDate = sittingDate
	}

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName qName: String?,
		attributes attributeDict: [String: String] = [:]
	) {
		currentText = ""
		let name = elementName.lowercased()
		if Constants.xmlVoteElements.contains(name) {
			currentVote = OntarioXMLVoteBuilder(sourceID: attributeDict[Constants.xmlIDAttribute] ?? UUID().uuidString)
		} else if let ballot = XMLBallotMapper.ballot(for: name) {
			currentBallot = ballot
		}
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		currentText += string
	}

	func parser(
		_ parser: XMLParser,
		didEndElement elementName: String,
		namespaceURI: String?,
		qualifiedName qName: String?
	) {
		let name = elementName.lowercased()
		let value = OntarioText.normalize(currentText)
		if Constants.xmlVoteElements.contains(name) {
			finalizeVote()
		} else if XMLBallotMapper.isBallotContainer(name) {
			currentBallot = nil
		} else {
			currentVote?.apply(element: name, value: value, ballot: currentBallot)
		}
		currentText = ""
	}

	private func finalizeVote() {
		guard let builder = currentVote else { return }
		if let vote = builder.makeVote(number: votes.count + Constants.oneBasedOffset, sittingDate: sittingDate) {
			votes.append(vote)
		}
		currentVote = nil
		currentBallot = nil
	}
}

private struct OntarioXMLVoteBuilder {
	let sourceID: String
	var voteID: Int?
	var parliament: Int = Constants.currentParliament
	var session: Int = Constants.currentSession
	var description = ""
	var billNumberCode = ""
	var result = ""
	var divisions: [OntarioDivisionSection] = []

	mutating func apply(element: String, value: String, ballot: String?) {
		guard !value.isEmpty else { return }
		if let ballot {
			appendMember(value, ballot: ballot)
		} else {
			applyVoteValue(element: element, value: value)
		}
	}

	func makeVote(number: Int, sittingDate: Date) -> RecordedVote? {
		guard !divisions.isEmpty else { return nil }
		let finalVoteID = voteID ?? OntarioStableIdentifier.voteID(sourceID: sourceID, date: sittingDate, index: number)
		let vote = RecordedVote(
			voteID: finalVoteID,
			parliament: parliament,
			session: session,
			number: number,
			date: sittingDate,
			descriptionEn: description,
			billNumberCode: billNumberCode,
			yea: count(ballot: Constants.ayeBallot),
			nay: count(ballot: Constants.nayBallot),
			paired: count(ballot: Constants.pairedBallot),
			resultEn: result,
			jurisdiction: Jurisdiction.ontario.rawValue
		)
		appendMemberVotes(to: vote, voteID: finalVoteID)
		return vote
	}

	private mutating func appendMember(_ value: String, ballot: String) {
		let names = OntarioText.memberList(from: value)
		guard !names.isEmpty else { return }
		divisions.append(OntarioDivisionSection(ballot: ballot, declaredCount: nil, memberNames: names))
	}

	private mutating func applyVoteValue(element: String, value: String) {
		if Constants.xmlIDElements.contains(element) {
			voteID = Int(value)
		} else if Constants.xmlParliamentElements.contains(element) {
			parliament = Int(value) ?? parliament
		} else if Constants.xmlSessionElements.contains(element) {
			session = Int(value) ?? session
		} else {
			applyStringVoteValue(element: element, value: value)
		}
	}

	private mutating func applyStringVoteValue(element: String, value: String) {
		if Constants.xmlDescriptionElements.contains(element) {
			description = value
		} else if Constants.xmlBillElements.contains(element) {
			billNumberCode = value
		} else if Constants.xmlResultElements.contains(element) {
			result = value
		}
	}

	private func count(ballot: String) -> Int {
		divisions
			.filter { $0.ballot == ballot }
			.reduce(Constants.zero) { $0 + $1.memberNames.count }
	}

	private func appendMemberVotes(to vote: RecordedVote, voteID: Int) {
		for division in divisions {
			for memberName in division.memberNames {
				let memberVote = MemberVote(
					voteID: voteID,
					memberID: OntarioStableIdentifier.memberID(name: memberName),
					recordedVote: division.ballot,
					jurisdiction: Jurisdiction.ontario.rawValue
				)
				vote.memberVotes.append(memberVote)
				memberVote.vote = vote
			}
		}
	}
}

private enum XMLBallotMapper {
	static func ballot(for element: String) -> String? {
		if Constants.xmlAyeElements.contains(element) {
			return Constants.ayeBallot
		}
		if Constants.xmlNayElements.contains(element) {
			return Constants.nayBallot
		}
		if Constants.xmlPairedElements.contains(element) {
			return Constants.pairedBallot
		}
		return nil
	}

	static func isBallotContainer(_ element: String) -> Bool {
		ballot(for: element) != nil
	}
}

private enum OntarioText {
	static func normalize(_ text: String) -> String {
		let normalized = decodeEntities(text)
			.replacingOccurrences(of: "\u{00a0}", with: " ")
			.split { $0.isWhitespace }
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return removeSpacingBeforePunctuation(normalized)
	}

	static func strippingTags(from html: String) -> String {
		html.replacing(Constants.tagPattern, with: " ")
	}

	static func memberList(from text: String) -> [String] {
		normalize(text)
			.split(separator: Constants.memberSeparator)
			.map { normalize(String($0)) }
			.filter { !$0.isEmpty }
	}

	private static func decodeEntities(_ text: String) -> String {
		text
			.replacingOccurrences(of: "&nbsp;", with: " ")
			.replacingOccurrences(of: "&#160;", with: " ")
			.replacingOccurrences(of: "&amp;", with: "&")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#039;", with: "'")
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
	}

	private static func removeSpacingBeforePunctuation(_ text: String) -> String {
		text
			.replacingOccurrences(of: " ,", with: ",")
			.replacingOccurrences(of: " .", with: ".")
			.replacingOccurrences(of: " :", with: ":")
			.replacingOccurrences(of: " ;", with: ";")
	}
}

private enum OntarioStableIdentifier {
	static func voteID(sourceID: String, date: Date, index: Int) -> Int {
		let day = Constants.dayFormatter.string(from: date)
		return stablePositiveInt("ontario-vote|\(day)|\(sourceID)|\(index)")
	}

	static func memberID(name: String) -> Int {
		stablePositiveInt("ontario-member|\(OntarioText.normalize(name).lowercased())")
	}

	private static func stablePositiveInt(_ value: String) -> Int {
		var hash = Constants.fnvOffsetBasis
		for byte in value.utf8 {
			hash ^= UInt64(byte)
			hash &*= Constants.fnvPrime
		}
		return Int(hash & Constants.positiveIntMask)
	}
}

private enum Constants {
	static let zero = 0
	static let oneBasedOffset = 1
	static let currentParliament = 44
	static let currentSession = 1
	static let fnvOffsetBasis: UInt64 = 14_695_981_039_346_656_037
	static let fnvPrime: UInt64 = 1_099_511_628_211
	static let positiveIntMask: UInt64 = 0x7FFF_FFFF
	static let memberSeparator: Character = ";"
	static let xmlIDAttribute = "id"
	static let carriedText = "Carried"
	static let lostText = "Lost"
	static let divisionText = "division"
	static let ayeBallot = "Aye"
	static let nayBallot = "Nay"
	static let pairedBallot = "Paired"
	static let ayesLower = "ayes"
	static let yeasLower = "yeas"
	static let naysLower = "nays"
	static let pairedLower = "paired"
	static let abstainedLower = "abstain"
	static var eventPattern: Regex<(Substring, Substring)> { /<!-- Event output starts -->(?s:(.*?))<!-- Event output ends -->/ }
	static var tableIDPattern: Regex<(Substring, Substring)> { /<table[^>]*\bid="([^"]+)"/ }
	static var englishCellPattern: Regex<(Substring, Substring)> { /<td[^>]*\blang="en"[^>]*>(?s:(.*?))<\/td>/ }
	static var divisionHeaderPattern: Regex<(Substring, Substring, Substring)> {
		/<h5[^>]*class="[^"]*divisionHeader[^"]*"[^>]*>(?s:(.*?))\((\d+)\)<\/h5>/
	}
	static var tableCellPattern: Regex<(Substring, Substring)> { /<td[^>]*>(?s:(.*?))<\/td>/ }
	static var tagPattern: Regex<Substring> { /<[^>]+>/ }
	static var billPattern: Regex<Substring> { /Bill\s+[0-9]+[A-Za-z]?/ }
	static var parliamentSessionLabelPattern: Regex<(Substring, Substring, Substring)> {
		/Parliament\s+([0-9]+)\s+Session\s+([0-9]+)/
	}
	static var parliamentSessionOrdinalPattern: Regex<(Substring, Substring, Substring)> {
		/([0-9]+)(?:st|nd|rd|th)\s+Parliament,\s+([0-9]+)(?:st|nd|rd|th)\s+Session/
	}
	static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: zero)
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	static let xmlVoteElements = Set(["vote", "recordedvote", "division"])
	static let xmlIDElements = Set(["id", "voteid", "divisionid", "number"])
	static let xmlParliamentElements = Set(["parliament", "legislature"])
	static let xmlSessionElements = Set(["session"])
	static let xmlDescriptionElements = Set(["description", "motion", "motiontext", "question", "title"])
	static let xmlBillElements = Set(["bill", "billnumber", "billnumbercode", "billcode"])
	static let xmlResultElements = Set(["result", "outcome", "status"])
	static let xmlAyeElements = Set(["aye", "ayes", "yea", "yeas", "for"])
	static let xmlNayElements = Set(["nay", "nays", "no", "against"])
	static let xmlPairedElements = Set(["paired", "pair", "pairs", "abstained", "abstentions"])
}

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
