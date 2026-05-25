//
//  ParliamentDTOs.swift
//  epac
//
//  Plain domain/value models for parliamentary data. These intentionally avoid
//  SwiftData, SwiftUI, and UIKit so parsing, tests, and previews can operate
//  without a persistence container or UI runtime.
//

import Foundation

struct ParliamentMemberDTO: Identifiable, Codable, Hashable, Sendable {
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
	let jurisdiction: Jurisdiction

	init(
		name: String,
		memberID: Int,
		lastName: String,
		firstName: String,
		photoURL: URL,
		riding: String,
		province: Province,
		party: Party,
		websiteURL: URL?,
		imageData: Data?,
		fromDateTime: Date?,
		toDateTime: Date?,
		email: String?,
		hillPhone: String?,
		constituencyPhone: String?,
		constituencyAddress: String?,
		contactFetched: Bool,
		jurisdiction: Jurisdiction = .federal
	) {
		self.name = name
		self.memberID = memberID
		self.lastName = lastName
		self.firstName = firstName
		self.photoURL = photoURL
		self.riding = riding
		self.province = province
		self.party = party
		self.websiteURL = websiteURL
		self.imageData = imageData
		self.fromDateTime = fromDateTime
		self.toDateTime = toDateTime
		self.email = email
		self.hillPhone = hillPhone
		self.constituencyPhone = constituencyPhone
		self.constituencyAddress = constituencyAddress
		self.contactFetched = contactFetched
		self.jurisdiction = jurisdiction
	}

	var id: String { "\(jurisdiction.rawValue)::\(name)" }
}

struct ConstituencyDTO: Identifiable, Codable, Hashable, Sendable {
	let name: String
	let province: Province
	let currentMemberFirstName: String
	let currentMemberLastName: String
	let currentMemberParty: Party

	var id: String { name }
}

struct SpeechMessageDTO: Identifiable, Codable, Hashable, Sendable {
	let firstName: String
	let lastName: String
	let partyAbbreviation: String
	let ridingName: String
	let hansardID: String
	let content: String
	let timestamp: Date

	var id: String { hansardID }
}

struct SpeechDTO: Identifiable, Codable, Hashable, Sendable {
	let messages: [SpeechMessageDTO]
	let hansardID: String
	let currentMessageID: String?
	let date: Date
	let length: Int
	let title: String

	var id: String { hansardID }
}

struct SubjectOfBusinessDTO: Identifiable, Codable, Hashable, Sendable {
	let title: String
	let hansardID: String
	let speeches: [SpeechDTO]
	let currentSpeechID: String?

	var id: String { hansardID }
}

struct OrderOfBusinessDTO: Identifiable, Codable, Hashable, Sendable {
	let hansardID: String
	let catchline: String
	let subjects: [SubjectOfBusinessDTO]

	var id: String { hansardID }
}

struct HansardDTO: Identifiable, Codable, Hashable, Sendable {
	let date: Date
	let hansardID: String
	let parliamentNumber: Int
	let sessionNumber: Int
	let orders: [OrderOfBusinessDTO]

	var id: String { hansardID }
}
