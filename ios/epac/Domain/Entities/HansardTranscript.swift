//
//  HansardTranscript.swift
//  epac
//

import Foundation

enum Jurisdiction: Hashable, Codable, Sendable {
	case houseOfCommons
	case provincial(Province)

	var id: String {
		switch self {
		case .houseOfCommons:
			return "house-of-commons"
		case .provincial(let province):
			return "provincial-\(province.shortCode.lowercased())"
		}
	}
}

struct SpeechMessageRecord: Identifiable, Codable, Hashable, Sendable {
	let speechID: String
	let firstName: String
	let lastName: String
	let partyAbbreviation: String
	let ridingName: String
	let hansardID: String
	let content: String
	let timestamp: Date

	var id: String { hansardID }
}

struct HansardSpeechRecord: Identifiable, Codable, Hashable, Sendable {
	let messages: [SpeechMessageRecord]
	let hansardID: String
	let currentMessageID: String?
	let date: Date
	let length: Int
	let title: String

	var id: String { hansardID }
}

struct SubjectOfBusinessRecord: Identifiable, Codable, Hashable, Sendable {
	let title: String
	let hansardID: String
	let speeches: [HansardSpeechRecord]
	let currentSpeechID: String?

	var id: String { hansardID }
}

struct OrderOfBusinessRecord: Identifiable, Codable, Hashable, Sendable {
	let hansardID: String
	let catchline: String
	let subjects: [SubjectOfBusinessRecord]

	var id: String { hansardID }
}

struct HansardTranscript: Identifiable, Codable, Hashable, Sendable {
	let jurisdiction: Jurisdiction
	let sittingDate: Date
	let hansardID: String
	let parliamentNumber: Int?
	let sessionNumber: Int?
	let orders: [OrderOfBusinessRecord]

	var id: String { "\(jurisdiction.id)-\(hansardID)" }

	var subjects: [SubjectOfBusinessRecord] {
		orders.flatMap(\.subjects)
	}
}
