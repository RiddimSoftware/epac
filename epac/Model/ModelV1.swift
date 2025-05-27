//
//  Calendar.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftData
import Foundation
import UIKit
import CoreTransferable
import SwiftUI

enum SchemaV1: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
	static var models: [any PersistentModel.Type] {
		[
			SittingCalendar.self,
			Hansard.self,
			OrderOfBusiness.self,
			SubjectOfBusiness.self,
			ParliamentMember.self,
			Speech.self,
			SpeechMessage.self
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
		var hansardID: String
		var content: String
		var timestamp: Date
		init(firstName: String, lastName: String, hansardID: String, content: String, timestamp: Date) {
			self.firstName = firstName
			self.lastName = lastName
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
//		init(xml: String) {
//			let hansard = XMLBro(xml: xml).parseXML().hansard()
//			date = hansard.date
//			hansardID = hansard.hansardID
//			parliamentNumber = hansard.parliamentNumber
//			sessionNumber = hansard.sessionNumber
//			orders = hansard.orders
//		}
	}
}

enum Province: String, Codable {
	case BC = "British Columbia"
	case Alberta = "Alberta"
	case Saskatchewan = "Saskatchewan"
	case Manitoba = "Manitoba"
	case Ontario = "Ontario"
	case Quebec = "Quebec"
	case NB = "New Brunswick"
	case PEI = "Prince Edward Island"
	case NS = "Nova Scotia"
	case NL = "Newfoundland and Labrador"
	case Yukon = "Yukon"
	case NWT = "Northwest Territories"
	case Nunavut = "Nunavut"
}

enum Party: Codable, CaseIterable {
	case conservative
	case liberal
	case newdemocratic
	case bloc
	case green
	case independent

	var abbreviation: String {
		switch self {
			case .conservative:     return "CPC"
			case .liberal:          return "Lib"
			case .newdemocratic:    return "NDP"
			case .bloc:             return "BQ"
			case .green:            return "GP"
			case .independent:      return "Ind"
		}
	}

	var localizedAbbreviation: String {
		switch self {
			case .conservative:     return NSLocalizedString("CPC", comment: "")
			case .liberal:          return NSLocalizedString("Lib", comment: "")
			case .newdemocratic:    return NSLocalizedString("NDP", comment: "")
			case .bloc:             return NSLocalizedString("BQ", comment: "")
			case .green:            return NSLocalizedString("GP", comment: "")
			case .independent:      return NSLocalizedString("Ind", comment: "")
		}
	}

	var image: UIImage? {
		return UIImage(named: self.abbreviation)
	}

	var fullName: String {
		switch self {
			case .conservative:     return NSLocalizedString("Conservative", comment: "")
			case .liberal:          return NSLocalizedString("Liberal", comment: "")
			case .newdemocratic:    return NSLocalizedString("New Democratic Party", comment: "")
			case .bloc:             return NSLocalizedString("Bloc Québécois", comment: "")
			case .green:            return NSLocalizedString("Green Party", comment: "")
			case .independent:      return NSLocalizedString("Independent", comment: "")
		}
	}

	var shortName: String {
		switch self {
			case .conservative:     return NSLocalizedString("Conservative", comment: "")
			case .liberal:          return NSLocalizedString("Liberal", comment: "")
			case .newdemocratic:    return NSLocalizedString("NDP", comment: "")
			case .bloc:             return NSLocalizedString("Bloc Québécois", comment: "")
			case .green:            return NSLocalizedString("Green Party", comment: "")
			case .independent:      return NSLocalizedString("Independent", comment: "")
		}
	}

	var colour: UIColor {
		switch self {
			case .conservative:     return UIColor(rgb: 0x1A4782)
			case .liberal:          return UIColor(rgb: 0xd71920)
			case .newdemocratic:    return UIColor(rgb: 0xF37021)
			case .bloc:             return UIColor(rgb: 0x33B2CC)
			case .green:            return UIColor(rgb: 0x3D9B35)
			case .independent:            return UIColor.darkText
		}
	}

	static func partyWithAbbreviation(_ name: String) -> Party {
		if name == Party.conservative.localizedAbbreviation {
			return .conservative
		} else if name == Party.liberal.localizedAbbreviation {
			return .liberal
		} else if name == Party.newdemocratic.localizedAbbreviation {
			return .newdemocratic
		} else if name == Party.bloc.localizedAbbreviation {
			return .bloc
		} else if name == Party.green.localizedAbbreviation {
			return .green
		}
		return .independent
	}
}
