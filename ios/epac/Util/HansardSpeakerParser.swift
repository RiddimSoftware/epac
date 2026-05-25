import Foundation

struct HansardSpeakerParser {
	struct ParsedSpeaker {
		let firstName: String
		let lastName: String?
		let partyAbbreviation: String
		let ridingName: String
	}

	static func parse(_ speakerText: String) -> ParsedSpeaker {
		let details = affiliationDetails(from: normalizedSpeakerText(speakerText))
		let names = speakerNameParts(from: details.speakerName)
		return ParsedSpeaker(
			firstName: names.firstName,
			lastName: names.lastName,
			partyAbbreviation: details.partyAbbreviation,
			ridingName: details.ridingName
		)
	}

	private static func normalizedSpeakerText(_ text: String) -> String {
		text.replacingOccurrences(of: "Mme ", with: "Mme. ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func affiliationDetails(from text: String) -> (speakerName: String, partyAbbreviation: String, ridingName: String) {
		let speakerName = parseNameSegment(from: text)
		guard let details = parenthesizedDetails(in: text) else {
			return (speakerName: speakerName, partyAbbreviation: "", ridingName: "")
		}
		return (
			speakerName: speakerName,
			partyAbbreviation: parsePartySegment(from: details),
			ridingName: parseRidingSegment(from: details)
		)
	}

	private static func parseNameSegment(from text: String) -> String {
		guard let firstParenIndex = text.firstIndex(of: "(") else {
			return text
		}
		return String(text[..<firstParenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func parenthesizedDetails(in text: String) -> String? {
		guard let firstParenIndex = text.firstIndex(of: "("), let lastParenIndex = text.lastIndex(of: ")") else {
			return nil
		}
		let detailsStartIndex = text.index(after: firstParenIndex)
		return String(text[detailsStartIndex..<lastParenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func parsePartySegment(from details: String) -> String {
		guard let lastCommaIndex = details.lastIndex(of: ",") else {
			return ""
		}
		let party = String(details[details.index(after: lastCommaIndex)...])
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return party.removingSuffix(".")
	}

	private static func parseRidingSegment(from details: String) -> String {
		guard let lastCommaIndex = details.lastIndex(of: ",") else {
			return details
		}
		let ridingOrRole = String(details[..<lastCommaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
		return parseRidingFromRidingOrRole(ridingOrRole)
	}

	private static func parseRidingFromRidingOrRole(_ text: String) -> String {
		if let roleCommaIndex = text.lastIndex(of: ",") {
			return String(text[text.index(after: roleCommaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return text.contains("(") ? "" : text
	}

	private static func speakerNameParts(from speakerName: String) -> (firstName: String, lastName: String?) {
		let cleanNames = speakerName
			.split(separator: " ")
			.filter { !speakerTitleWords.contains(String($0)) }
		return (firstName: cleanNames.dropLast().joined(separator: " "), lastName: cleanNames.last.map(String.init))
	}

	private static let speakerTitleWords = [
		"Hon.",
		"Rt.",
		"Mr.",
		"Ms.",
		"Mrs.",
		"Mme.",
		"Mme",
		"M.",
		"L'hon.",
		"L\u{2019}hon.",
		"Dr.",
		"The",
		"Hon",
		"Rt",
		"Right"
	]
}

private extension String {
	func removingSuffix(_ suffix: String) -> String {
		hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
	}
}
