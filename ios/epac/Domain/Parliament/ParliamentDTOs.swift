//
//  ParliamentDTOs.swift
//  epac
//
//  Plain domain/value models for parliamentary data. These intentionally avoid
//  SwiftData, SwiftUI, and UIKit so parsing, tests, and previews can operate
//  without a persistence container or UI runtime.
//

import Foundation

struct ParliamentMemberDTO: Identifiable, Codable, Hashable {
	let name: String
	let memberID: Int
	let lastName: String
	let firstName: String
	let photoURL: URL
	let riding: String
	let province: Province
	let party: Party
	let websiteURL: URL?
	let imageData: Data?
	let fromDateTime: Date?
	let toDateTime: Date?
	let email: String?
	let hillPhone: String?
	let constituencyPhone: String?
	let constituencyAddress: String?
	let contactFetched: Bool

	var id: String { name }
}

struct ConstituencyDTO: Identifiable, Codable, Hashable {
	let name: String
	let province: Province
	let currentMemberFirstName: String
	let currentMemberLastName: String
	let currentMemberParty: Party

	var id: String { name }
}

struct SpeechMessageDTO: Identifiable, Codable, Hashable {
	let firstName: String
	let lastName: String
	let partyAbbreviation: String
	let ridingName: String
	let hansardID: String
	let content: String
	let timestamp: Date

	var id: String { hansardID }
}

struct SpeechDTO: Identifiable, Codable, Hashable {
	let messages: [SpeechMessageDTO]
	let hansardID: String
	let currentMessageID: String?
	let date: Date
	let length: Int
	let title: String

	var id: String { hansardID }
}

struct SubjectOfBusinessDTO: Identifiable, Codable, Hashable {
	let title: String
	let hansardID: String
	let speeches: [SpeechDTO]
	let currentSpeechID: String?

	var id: String { hansardID }
}

struct OrderOfBusinessDTO: Identifiable, Codable, Hashable {
	let hansardID: String
	let catchline: String
	let subjects: [SubjectOfBusinessDTO]

	var id: String { hansardID }
}

struct HansardDTO: Identifiable, Codable, Hashable {
	let date: Date
	let hansardID: String
	let parliamentNumber: Int
	let sessionNumber: Int
	let orders: [OrderOfBusinessDTO]

	var id: String { hansardID }
}
