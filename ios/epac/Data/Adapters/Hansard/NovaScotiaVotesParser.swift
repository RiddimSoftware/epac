//
//  NovaScotiaVotesParser.swift
//  epac
//

import Foundation
import Kanna

enum NovaScotiaVotesParserError: Error {
	case invalidHTML
}

struct NovaScotiaVotesParser {
	func parse(document: String, sittingDate: Date) throws -> [RecordedVote] {
		guard let doc = try? HTML(html: document, encoding: .utf8) else {
			throw NovaScotiaVotesParserError.invalidHTML
		}
		let semanticVotes = parseSemanticVotes(in: doc, sittingDate: sittingDate)
		return semanticVotes.isEmpty ? parseTableVotes(in: doc, sittingDate: sittingDate) : semanticVotes
	}

	private func parseSemanticVotes(in doc: HTMLDocument, sittingDate: Date) -> [RecordedVote] {
		doc.css("[data-recorded-vote]")
			.enumerated()
			.compactMap { offset, element in
				let draft = semanticDraft(from: element, fallbackNumber: offset + 1)
				return makeVote(from: draft, sittingDate: sittingDate, sequence: offset + 1)
			}
	}

	private func parseTableVotes(in doc: HTMLDocument, sittingDate: Date) -> [RecordedVote] {
		doc.css("table")
			.enumerated()
			.compactMap { offset, table in
				guard let draft = tableDraft(from: table, fallbackNumber: offset + 1) else { return nil }
				return makeVote(from: draft, sittingDate: sittingDate, sequence: offset + 1)
			}
	}

	private func semanticDraft(from element: XMLElement, fallbackNumber: Int) -> VoteDraft {
		VoteDraft(
			sourceID: intAttribute("data-vote-id", in: element),
			number: intAttribute("data-vote-number", in: element) ?? fallbackNumber,
			motion: textAttribute("data-motion", in: element) ?? firstText(in: element, selectors: ["[data-motion]", ".motion", "h2", "h3"]),
			billCode: textAttribute("data-bill", in: element),
			result: textAttribute("data-result", in: element) ?? firstText(in: element, selectors: ["[data-result]", ".result"]),
			members: semanticMembers(in: element)
		)
	}

	private func tableDraft(from table: XMLElement, fallbackNumber: Int) -> VoteDraft? {
		let rows = Array(table.css("tr"))
		guard let header = voteHeader(in: rows) else { return nil }
		let members = tableMembers(in: rows, header: header)
		guard !members.isEmpty else { return nil }
		return VoteDraft(
			sourceID: intAttribute("data-vote-id", in: table),
			number: intAttribute("data-vote-number", in: table) ?? fallbackNumber,
			motion: firstText(in: table, selectors: ["caption", "[data-motion]"]),
			billCode: textAttribute("data-bill", in: table),
			result: textAttribute("data-result", in: table) ?? inferredResult(from: table),
			members: members
		)
	}

	private func semanticMembers(in element: XMLElement) -> [VoteMember] {
		BallotKind.allCases.flatMap { ballot in
			members(in: element, for: ballot)
		}
	}

	private func members(in element: XMLElement, for ballot: BallotKind) -> [VoteMember] {
		ballot.selectors.flatMap { selector in
			element.css(selector).flatMap { section in
				memberRows(in: section, ballot: ballot)
			}
		}
	}

	private func memberRows(in section: XMLElement, ballot: BallotKind) -> [VoteMember] {
		let explicitMembers = Array(section.css("[data-member], [data-member-id]"))
		let candidateRows = explicitMembers.isEmpty ? Array(section.css("li, td, p")) : explicitMembers
		return candidateRows.compactMap { member(from: $0, ballot: ballot) }
	}

	private func member(from element: XMLElement, ballot: BallotKind) -> VoteMember? {
		let name = cleanMemberName(textAttribute("data-member", in: element) ?? element.text)
		guard !name.isEmpty, !ballot.headerTitles.contains(name.lowercased()) else { return nil }
		return VoteMember(name: name, memberID: intAttribute("data-member-id", in: element), ballot: ballot)
	}

	private func voteHeader(in rows: [XMLElement]) -> VoteTableHeader? {
		rows.compactMap { row in
			VoteTableHeader(cells: row.css("th, td").map { cleanText($0.text) })
		}.first
	}

	private func tableMembers(in rows: [XMLElement], header: VoteTableHeader) -> [VoteMember] {
		rows.dropFirst(header.rowOffset).flatMap { row in
			tableMembers(in: row, header: header)
		}
	}

	private func tableMembers(in row: XMLElement, header: VoteTableHeader) -> [VoteMember] {
		let cells = Array(row.css("td"))
		return header.columns.compactMap { column in
			guard column.index < cells.count else { return nil }
			return member(from: cells[column.index], ballot: column.ballot)
		}
	}

	private func makeVote(from draft: VoteDraft, sittingDate: Date, sequence: Int) -> RecordedVote? {
		guard !draft.members.isEmpty else { return nil }
		let voteID = draft.sourceID ?? stableVoteID(sittingDate: sittingDate, sequence: sequence)
		let vote = RecordedVote(
			voteID: voteID,
			parliament: Constants.defaultLegislature,
			session: Constants.defaultSession,
			number: draft.number ?? sequence,
			date: sittingDate,
			descriptionEn: draft.motion,
			billNumberCode: draft.billCode ?? billCode(from: draft.motion),
			yea: draft.count(.yea),
			nay: draft.count(.nay),
			paired: draft.nonVotingCount,
			resultEn: draft.result,
			jurisdiction: Jurisdiction.novaScotia.rawValue
		)
		attachMemberVotes(draft.members, voteID: voteID, to: vote)
		return vote
	}

	private func attachMemberVotes(_ members: [VoteMember], voteID: Int, to vote: RecordedVote) {
		for member in members {
			let row = MemberVote(
				voteID: voteID,
				memberID: member.memberID ?? stableMemberID(name: member.name),
				recordedVote: member.ballot.recordedVote,
				jurisdiction: Jurisdiction.novaScotia.rawValue
			)
			row.vote = vote
			vote.memberVotes.append(row)
		}
	}

	private func inferredResult(from element: XMLElement) -> String {
		let text = cleanText(element.text).lowercased()
		if text.contains("negatived") || text.contains("defeated") {
			return "Negatived"
		}
		if text.contains("carried") || text.contains("agreed to") {
			return "Carried"
		}
		return ""
	}

	private func billCode(from text: String) -> String {
		let pattern = #"(?i)\bBill\s+(?:No\.\s*)?([0-9A-Za-z-]+)"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
		let range = NSRange(text.startIndex..<text.endIndex, in: text)
		guard let match = regex.firstMatch(in: text, range: range),
			  let codeRange = Range(match.range(at: 1), in: text) else {
			return ""
		}
		return String(text[codeRange])
	}

	private func stableVoteID(sittingDate: Date, sequence: Int) -> Int {
		(Constants.voteNamespace * Constants.namespaceMultiplier)
			+ (dateKey(from: sittingDate) * Constants.voteSequenceMultiplier)
			+ sequence
	}

	private func dateKey(from date: Date) -> Int {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: Constants.gmtOffsetSeconds) ?? TimeZone.current
		let parts = calendar.dateComponents([.year, .month, .day], from: date)
		return ((parts.year ?? 0) * Constants.yearDateKeyMultiplier)
			+ ((parts.month ?? 0) * Constants.monthDateKeyMultiplier)
			+ (parts.day ?? 0)
	}

	private func stableMemberID(name: String) -> Int {
		let normalized = "nova-scotia:\(cleanMemberName(name).lowercased())"
		var hash: UInt64 = Constants.fnvOffset
		for byte in normalized.utf8 {
			hash ^= UInt64(byte)
			hash &*= Constants.fnvPrime
		}
		return Int(hash & Constants.memberIDMask)
	}

	private func intAttribute(_ name: String, in element: XMLElement) -> Int? {
		textAttribute(name, in: element).flatMap(Int.init)
	}

	private func textAttribute(_ name: String, in element: XMLElement) -> String? {
		guard let value = element[name].map(cleanText), !value.isEmpty else { return nil }
		return value
	}

	private func firstText(in element: XMLElement, selectors: [String]) -> String {
		selectors.lazy.compactMap { selector in
			element.css(selector).first?.text.map(cleanText)
		}.first ?? ""
	}

	private func cleanMemberName(_ value: String?) -> String {
		let text = cleanText(value)
		let prefixes = ["Hon. ", "HON. ", "Mr. ", "Mrs. ", "Ms. ", "Miss ", "Dr. "]
		return prefixes.reduce(text) { partial, prefix in
			partial.hasPrefix(prefix) ? String(partial.dropFirst(prefix.count)) : partial
		}
	}

	private func cleanText(_ value: String?) -> String {
		(value ?? "")
			.replacingOccurrences(of: "\u{00a0}", with: " ")
			.components(separatedBy: .whitespacesAndNewlines)
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}
}

private struct VoteDraft {
	let sourceID: Int?
	let number: Int?
	let motion: String
	let billCode: String?
	let result: String
	let members: [VoteMember]

	func count(_ ballot: BallotKind) -> Int {
		members.filter { $0.ballot == ballot }.count
	}

	var nonVotingCount: Int {
		members.filter { $0.ballot.isNonVoting }.count
	}
}

private struct VoteMember {
	let name: String
	let memberID: Int?
	let ballot: BallotKind
}

private struct VoteTableHeader {
	let rowOffset: Int = 1
	let columns: [VoteTableColumn]

	init?(cells: [String]) {
		let columns = cells.enumerated().compactMap { index, cell -> VoteTableColumn? in
			guard let ballot = BallotKind(header: cell) else { return nil }
			return VoteTableColumn(index: index, ballot: ballot)
		}
		guard columns.contains(where: { $0.ballot == .yea }),
		      columns.contains(where: { $0.ballot == .nay }) else {
			return nil
		}
		self.columns = columns
	}
}

private struct VoteTableColumn {
	let index: Int
	let ballot: BallotKind
}

private enum BallotKind: CaseIterable, Equatable {
	case yea
	case nay
	case paired
	case abstained
	case absent

	init?(header: String) {
		let text = header.lowercased()
		if ["yea", "yeas", "for", "aye", "ayes"].contains(text) {
			self = .yea
		} else if ["nay", "nays", "against", "opposed"].contains(text) {
			self = .nay
		} else if ["paired", "pairs"].contains(text) {
			self = .paired
		} else if ["abstained", "abstentions", "abstention"].contains(text) {
			self = .abstained
		} else if ["absent", "absences"].contains(text) {
			self = .absent
		} else {
			return nil
		}
	}

	var selectors: [String] {
		headerTitles.map { "[data-vote='\($0)'], [data-ballot='\($0)']" }
	}

	var headerTitles: [String] {
		switch self {
		case .yea:
			return ["yea", "yeas", "yes", "for", "aye", "ayes"]
		case .nay:
			return ["nay", "nays", "no", "against", "opposed"]
		case .paired:
			return ["paired", "pairs"]
		case .abstained:
			return ["abstained", "abstention", "abstentions"]
		case .absent:
			return ["absent", "absences"]
		}
	}

	var recordedVote: String {
		switch self {
		case .yea:
			return "Yea"
		case .nay:
			return "Nay"
		case .paired:
			return "Paired"
		case .abstained:
			return "Abstained"
		case .absent:
			return "Absent"
		}
	}

	var isNonVoting: Bool {
		self != .yea && self != .nay
	}
}

private enum Constants {
	static let gmtOffsetSeconds = 0
	static let yearDateKeyMultiplier = 10_000
	static let monthDateKeyMultiplier = 100
	static let defaultLegislature = 65
	static let defaultSession = 1
	static let voteNamespace = 65
	static let namespaceMultiplier = 10_000_000_000
	static let voteSequenceMultiplier = 100
	static let fnvOffset: UInt64 = 1_469_598_103_934_665_603
	static let fnvPrime: UInt64 = 1_099_511_628_211
	static let memberIDMask: UInt64 = 0x7fff_ffff
}
