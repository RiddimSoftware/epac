//
//  ModelV2.swift
//  epac
//
//  Created by Sunny on 2025-05-27.
//

import SwiftData
import Foundation
import UIKit
import CoreTransferable
import SwiftUI

typealias SittingCalendar = SchemaV2.SittingCalendar
typealias Hansard = SchemaV2.Hansard
typealias OrderOfBusiness = SchemaV2.OrderOfBusiness
typealias SubjectOfBusiness = SchemaV2.SubjectOfBusiness
typealias ParliamentMember = SchemaV2.ParliamentMember
typealias Speech = SchemaV2.Speech
typealias SpeechMessage = SchemaV2.SpeechMessage
typealias Constituency = SchemaV2.Constituency

enum SchemaV2: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
	static var models: [any PersistentModel.Type] {
		[
			SittingCalendar.self,
			Hansard.self,
			OrderOfBusiness.self,
			SubjectOfBusiness.self,
			ParliamentMember.self,
			Speech.self,
			SpeechMessage.self,
			Constituency.self
		]
	}

	@Model
	final class SittingCalendar {
		var year: Int
		var sittings: [Date]
		init(year: Int, sittings: [Date]) {
			self.year = year
			self.sittings = sittings
		}
	}

	@Model
	final class ParliamentMember: Hashable {
		var name:           String
		var lastName:       String
		var firstName:      String
		var photoURL: 			URL
		var riding:         String
		var province: Province
		var party:          Party
		var websiteURL:     URL?
		var imageData: Data?
		init(name: String, lastName: String, firstName: String, photoURL: URL, riding: String, province: Province, party: Party, websiteURL: URL? = nil) {
			self.name = name
			self.lastName = lastName
			self.firstName = firstName
			self.photoURL = photoURL
			self.riding = riding
			self.province = province
			self.party = party
			self.websiteURL = websiteURL
		}
		var isCurrentUser: Bool {
			return party == .liberal
		}
		static func == (lhs: ParliamentMember, rhs: ParliamentMember) -> Bool {
			return lhs.name == rhs.name
		}
		func hash(into hasher: inout Hasher) {
			hasher.combine(name)
		}
	}

	@Model
	final class Constituency: Hashable {
		var name: String
		var province: Province
		var currentMemberFirstName: String
		var currentMemberLastName: String
		var currentMemberParty: Party
		init(name: String, province: Province, currentMemberFirstName: String, currentMemberLastName: String, currentMemberParty: Party) {
			self.name = name
			self.province = province
			self.currentMemberFirstName = currentMemberFirstName
			self.currentMemberLastName = currentMemberLastName
			self.currentMemberParty = currentMemberParty
		}
	}

	@Model
	final class SubjectOfBusiness: Hashable {
		var title: String
		var hansardID: String
		var speeches: [Speech]
		var currentSpeech: Speech?
		init(title: String, hansardID: String, speeches: [Speech] = []) {
			self.title = title.trimmingCharacters(in: CharacterSet.whitespaces)
			self.hansardID = hansardID
			self.speeches = speeches
		}
		static func == (lhs: SubjectOfBusiness, rhs: SubjectOfBusiness) -> Bool {
			return lhs.hansardID == rhs.hansardID
		}
		func hash(into hasher: inout Hasher) {
			hasher.combine(hansardID)
		}
	}

	@Model
	final class OrderOfBusiness {
		var hansardID: String
		var catchline: String
		var subjects: [SubjectOfBusiness]
		init(hansardID: String, catchline: String, subjects: [SubjectOfBusiness] = []) {
			self.hansardID = hansardID
			self.catchline = catchline
			self.subjects = subjects
		}
	}

	@Model
	// <ParaText>
	final class SpeechMessage {
		var firstName: String
		var lastName: String
		var partyAbbreviation: String
		var ridingName: String
		var hansardID: String
		var content: String
		var timestamp: Date
		init(firstName: String, lastName: String, partyAbbreviation: String, ridingName: String, hansardID: String, content: String, timestamp: Date) {
			self.firstName = firstName
			self.lastName = lastName
			self.partyAbbreviation = partyAbbreviation
			self.ridingName = ridingName
			self.hansardID = hansardID
			self.content = content
			self.timestamp = timestamp
		}
	}

	@Model
	// <Intervention>
	final class Speech: Hashable {
		var messages: [SpeechMessage]
		var hansardID: String
		var currentMessage: SpeechMessage?
		var date: Date
		var length: Int
		var title: String
		init(messages: [SpeechMessage], hansardID: String, date: Date, title: String) {
			self.messages = messages
			self.hansardID = hansardID
			self.date = date
			self.length = messages.count
			self.title = title
		}
		static func == (lhs: Speech, rhs: Speech) -> Bool {
			return lhs.hansardID == rhs.hansardID
		}
		func hash(into hasher: inout Hasher) {
			hasher.combine(hansardID)
		}
	}

	@Model
	final class Hansard {
		var date: Date
		var hansardID: String
		var parliamentNumber: Int
		var sessionNumber: Int
		var orders: [OrderOfBusiness]
		init(date: Date, hansardID: String, parliamentNumber: Int, sessionNumber: Int, orders: [OrderOfBusiness] = []) {
			self.date = date
			self.hansardID = hansardID
			self.parliamentNumber = parliamentNumber
			self.sessionNumber = sessionNumber
			self.orders = orders
		}
		init(xml: String) {
			let hansard = XMLBro(xml: xml).parseXML().hansard()
			date = hansard.date
			hansardID = hansard.hansardID
			parliamentNumber = hansard.parliamentNumber
			sessionNumber = hansard.sessionNumber
			orders = hansard.orders
		}
	}
}
