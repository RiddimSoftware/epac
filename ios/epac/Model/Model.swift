//
//  Model.swift
//  epac
//
//  Created by Sunny on 2026-01-27.
//

import SwiftData
import Foundation
import UIKit
import SwiftUI

typealias SittingCalendar = SchemaV4.SittingCalendar
typealias Hansard = SchemaV4.Hansard
typealias OrderOfBusiness = SchemaV4.OrderOfBusiness
typealias SubjectOfBusiness = SchemaV4.SubjectOfBusiness
typealias ParliamentMember = SchemaV4.ParliamentMember
typealias Speech = SchemaV4.Speech
typealias SpeechMessage = SchemaV4.SpeechMessage
typealias Constituency = SchemaV4.Constituency
typealias TravelClaim = SchemaV4.TravelClaim
typealias TravelExpenditureDetail = SchemaV4.TravelExpenditureDetail
typealias HospitalityExpenditure = SchemaV4.HospitalityExpenditure
typealias ContractExpenditure = SchemaV4.ContractExpenditure
typealias SummaryExpenditure = SchemaV4.SummaryExpenditure

enum SchemaV3: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
	static var models: [any PersistentModel.Type] {
		[
			SittingCalendar.self,
			Hansard.self,
			OrderOfBusiness.self,
			SubjectOfBusiness.self,
			ParliamentMember.self,
			Speech.self,
			SpeechMessage.self,
			Constituency.self,
			SummaryExpenditure.self,
			TravelClaim.self,
			TravelExpenditureDetail.self,
			HospitalityExpenditure.self,
			ContractExpenditure.self
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
		@Attribute(.unique) var name:           String
		var memberID: Int
		var lastName:       String
		var firstName:      String
		var photoURL: 			URL
		var riding:         String
		var province: Province
		var party:          Party
		var websiteURL:     URL?
		var imageData: Data?
		var fromDateTime: Date?
		var toDateTime: Date?
		init(name: String, lastName: String, firstName: String, photoURL: URL, riding: String, province: Province, party: Party, websiteURL: URL? = nil, memberID: Int = 0, fromDateTime: Date? = nil, toDateTime: Date? = nil) {
			self.name = name
			self.memberID = memberID
			self.lastName = lastName
			self.firstName = firstName
			self.photoURL = photoURL
			self.riding = riding
			self.province = province
			self.party = party
			self.websiteURL = websiteURL
			self.fromDateTime = fromDateTime
			self.toDateTime = toDateTime
		}
		var initials: String {
			let first = firstName.first.map(String.init) ?? ""
			let last = lastName.first.map(String.init) ?? ""
			return first + last
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
	                var currentSpeechID: String?
	                init(title: String, hansardID: String, speeches: [Speech] = []) {			self.title = title.trimmingCharacters(in: CharacterSet.whitespaces)
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
	        final class Speech: Hashable {
	                var messages: [SpeechMessage]
	                var hansardID: String
	                var currentMessage: SpeechMessage?
	                var currentMessageID: String?
	                var date: Date
	                var length: Int
	                var title: String
	                init(messages: [SpeechMessage], hansardID: String, date: Date, title: String) {			self.messages = messages
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
		var orders: [SchemaV3.OrderOfBusiness]
		init(date: Date, hansardID: String, parliamentNumber: Int, sessionNumber: Int, orders: [SchemaV3.OrderOfBusiness] = []) {
			self.date = date
			self.hansardID = hansardID
			self.parliamentNumber = parliamentNumber
			self.sessionNumber = sessionNumber
			self.orders = orders
		}
	}

    @Model
    final class SummaryExpenditure: Identifiable {
		var firstName: String
        var lastName: String
        var constituency: String
        var caucus: String
        var salaries: Double
        var travel: Double
        var hospitality: Double
        var contracts: Double
		var year: Int
		var quarter: Int
		var travelURL: String?
		var hospitalityURL: String?
		var contractsURL: String?
		
		@Relationship(deleteRule: .cascade) var travelClaims: [TravelClaim] = []
		@Relationship(deleteRule: .cascade) var hospitalityDetails: [HospitalityExpenditure] = []
		@Relationship(deleteRule: .cascade) var contractDetails: [ContractExpenditure] = []

		var total: Double {
			return travel + hospitality + contracts
		}

		var party: Party {
			return Party.partyWithAbbreviation(caucus)
		}

		init(firstName: String, lastName: String, constituency: String, caucus: String, salaries: Double, travel: Double, hospitality: Double, contracts: Double, year: Int, quarter: Int, travelURL: String? = nil, hospitalityURL: String? = nil, contractsURL: String? = nil) {
			self.firstName = firstName
			self.lastName = lastName
            self.constituency = constituency
            self.caucus = caucus
            self.salaries = salaries
            self.travel = travel
            self.hospitality = hospitality
            self.contracts = contracts
			self.year = year
			self.quarter = quarter
			self.travelURL = travelURL
			self.hospitalityURL = hospitalityURL
			self.contractsURL = contractsURL
        }
    }

    @Model
    final class TravelClaim: Identifiable {
        var claimID: String
        var startDate: Date
        var endDate: Date
        var transportation: Double
        var accommodations: Double
        var mealsAndIncidentals: Double
        var total: Double
        var summary: SummaryExpenditure?
        @Relationship(deleteRule: .cascade) var details: [TravelExpenditureDetail] = []

        init(claimID: String, startDate: Date, endDate: Date, transportation: Double, accommodations: Double, mealsAndIncidentals: Double, total: Double) {
            self.claimID = claimID
            self.startDate = startDate
            self.endDate = endDate
            self.transportation = transportation
            self.accommodations = accommodations
            self.mealsAndIncidentals = mealsAndIncidentals
            self.total = total
        }
    }

    @Model
    final class TravelExpenditureDetail: Identifiable {
        var travellerName: String?
        var travellerType: String
        var purposeOfTravel: String
        var date: Date
        var departure: String
        var destination: String
        var claim: TravelClaim?

        init(travellerName: String? = nil, travellerType: String, purposeOfTravel: String, date: Date, departure: String, destination: String) {
            self.travellerName = travellerName
            self.travellerType = travellerType
            self.purposeOfTravel = purposeOfTravel
            self.date = date
            self.departure = departure
            self.destination = destination
        }
    }

    @Model
    final class HospitalityExpenditure: Identifiable {
        var date: Date
        var location: String
        var totalOfAttendees: Int
        var purposeOfHospitality: String
        var total: Double
        var typeOfEvent: String
        var claim: String
        var supplier: String
        var memberID: Int
		var year: Int
		var quarter: Int
		var summary: SummaryExpenditure?

        init(date: Date, location: String, totalOfAttendees: Int, purposeOfHospitality: String, total: Double, typeOfEvent: String, claim: String, supplier: String, memberID: Int, year: Int, quarter: Int) {
            self.date = date
            self.location = location
            self.totalOfAttendees = totalOfAttendees
            self.purposeOfHospitality = purposeOfHospitality
            self.total = total
            self.typeOfEvent = typeOfEvent
            self.claim = claim
            self.supplier = supplier
            self.memberID = memberID
			self.year = year
			self.quarter = quarter
        }
    }

    @Model
    final class ContractExpenditure: Identifiable {
        var supplier: String
        var details: String
        var date: Date
        var total: Double
        var memberID: Int
		var year: Int
		var quarter: Int
		var summary: SummaryExpenditure?

        init(supplier: String, details: String, date: Date, total: Double, memberID: Int, year: Int, quarter: Int) {
            self.supplier = supplier
            self.details = details
            self.date = date
            self.total = total
            self.memberID = memberID
			self.year = year
			self.quarter = quarter
        }
    }
}

enum SchemaV4: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(4, 0, 0) }
	static var models: [any PersistentModel.Type] {
		[
			SittingCalendar.self,
			Hansard.self,
			OrderOfBusiness.self,
			SubjectOfBusiness.self,
			ParliamentMember.self,
			Speech.self,
			SpeechMessage.self,
			Constituency.self,
			SummaryExpenditure.self,
			TravelClaim.self,
			TravelExpenditureDetail.self,
			HospitalityExpenditure.self,
			ContractExpenditure.self
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
		@Attribute(.unique) var name:           String
		var memberID: Int
		var lastName:       String
		var firstName:      String
		var photoURL: 			URL
		var riding:         String
		var province: Province
		var party:          Party
		var websiteURL:     URL?
		var imageData: Data?
		var fromDateTime: Date?
		var toDateTime: Date?
		var email: String?
		var hillPhone: String?
		var constituencyPhone: String?
		var constituencyAddress: String?
		var contactFetched: Bool
		init(name: String, lastName: String, firstName: String, photoURL: URL, riding: String, province: Province, party: Party, websiteURL: URL? = nil, memberID: Int = 0, fromDateTime: Date? = nil, toDateTime: Date? = nil) {
			self.name = name
			self.memberID = memberID
			self.lastName = lastName
			self.firstName = firstName
			self.photoURL = photoURL
			self.riding = riding
			self.province = province
			self.party = party
			self.websiteURL = websiteURL
			self.fromDateTime = fromDateTime
			self.toDateTime = toDateTime
			self.email = nil
			self.hillPhone = nil
			self.constituencyPhone = nil
			self.constituencyAddress = nil
			self.contactFetched = false
		}
		var initials: String {
			let first = firstName.first.map(String.init) ?? ""
			let last = lastName.first.map(String.init) ?? ""
			return first + last
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
		var currentSpeechID: String?
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
	final class Speech: Hashable {
		var messages: [SpeechMessage]
		var hansardID: String
		var currentMessage: SpeechMessage?
		var currentMessageID: String?
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

	@Model
	final class SummaryExpenditure: Identifiable {
		var firstName: String
		var lastName: String
		var constituency: String
		var caucus: String
		var salaries: Double
		var travel: Double
		var hospitality: Double
		var contracts: Double
		var year: Int
		var quarter: Int
		var travelURL: String?
		var hospitalityURL: String?
		var contractsURL: String?

		@Relationship(deleteRule: .cascade) var travelClaims: [TravelClaim] = []
		@Relationship(deleteRule: .cascade) var hospitalityDetails: [HospitalityExpenditure] = []
		@Relationship(deleteRule: .cascade) var contractDetails: [ContractExpenditure] = []

		var total: Double {
			return travel + hospitality + contracts
		}

		var party: Party {
			return Party.partyWithAbbreviation(caucus)
		}

		init(firstName: String, lastName: String, constituency: String, caucus: String, salaries: Double, travel: Double, hospitality: Double, contracts: Double, year: Int, quarter: Int, travelURL: String? = nil, hospitalityURL: String? = nil, contractsURL: String? = nil) {
			self.firstName = firstName
			self.lastName = lastName
			self.constituency = constituency
			self.caucus = caucus
			self.salaries = salaries
			self.travel = travel
			self.hospitality = hospitality
			self.contracts = contracts
			self.year = year
			self.quarter = quarter
			self.travelURL = travelURL
			self.hospitalityURL = hospitalityURL
			self.contractsURL = contractsURL
		}
	}

	@Model
	final class TravelClaim: Identifiable {
		var claimID: String
		var startDate: Date
		var endDate: Date
		var transportation: Double
		var accommodations: Double
		var mealsAndIncidentals: Double
		var total: Double
		var summary: SummaryExpenditure?
		@Relationship(deleteRule: .cascade) var details: [TravelExpenditureDetail] = []

		init(claimID: String, startDate: Date, endDate: Date, transportation: Double, accommodations: Double, mealsAndIncidentals: Double, total: Double) {
			self.claimID = claimID
			self.startDate = startDate
			self.endDate = endDate
			self.transportation = transportation
			self.accommodations = accommodations
			self.mealsAndIncidentals = mealsAndIncidentals
			self.total = total
		}
	}

	@Model
	final class TravelExpenditureDetail: Identifiable {
		var travellerName: String?
		var travellerType: String
		var purposeOfTravel: String
		var date: Date
		var departure: String
		var destination: String
		var claim: TravelClaim?

		init(travellerName: String? = nil, travellerType: String, purposeOfTravel: String, date: Date, departure: String, destination: String) {
			self.travellerName = travellerName
			self.travellerType = travellerType
			self.purposeOfTravel = purposeOfTravel
			self.date = date
			self.departure = departure
			self.destination = destination
		}
	}

	@Model
	final class HospitalityExpenditure: Identifiable {
		var date: Date
		var location: String
		var totalOfAttendees: Int
		var purposeOfHospitality: String
		var total: Double
		var typeOfEvent: String
		var claim: String
		var supplier: String
		var memberID: Int
		var year: Int
		var quarter: Int
		var summary: SummaryExpenditure?

		init(date: Date, location: String, totalOfAttendees: Int, purposeOfHospitality: String, total: Double, typeOfEvent: String, claim: String, supplier: String, memberID: Int, year: Int, quarter: Int) {
			self.date = date
			self.location = location
			self.totalOfAttendees = totalOfAttendees
			self.purposeOfHospitality = purposeOfHospitality
			self.total = total
			self.typeOfEvent = typeOfEvent
			self.claim = claim
			self.supplier = supplier
			self.memberID = memberID
			self.year = year
			self.quarter = quarter
		}
	}

	@Model
	final class ContractExpenditure: Identifiable {
		var supplier: String
		var details: String
		var date: Date
		var total: Double
		var memberID: Int
		var year: Int
		var quarter: Int
		var summary: SummaryExpenditure?

		init(supplier: String, details: String, date: Date, total: Double, memberID: Int, year: Int, quarter: Int) {
			self.supplier = supplier
			self.details = details
			self.date = date
			self.total = total
			self.memberID = memberID
			self.year = year
			self.quarter = quarter
		}
	}
}

	enum Province: String, Codable, CaseIterable, Identifiable {
	var id: Self { self }

	var shortCode: String {
		switch self {
			case .Alberta: return "AB"
			case .BC: return "BC"
			case .Manitoba: return "MB"
			case .NB: return "NB"
			case .NL: return "NL"
			case .NWT: return "NT"
			case .NS: return "NS"
			case .Nunavut: return "NU"
			case .Ontario: return "ON"
			case .PEI: return "PE"
			case .Quebec: return "QC"
			case .Saskatchewan: return "SK"
			case .Yukon: return "YT"
		}
	}

	case Alberta = "Alberta"
	case BC = "British Columbia"
	case Manitoba = "Manitoba"
	case NB = "New Brunswick"
	case NL = "Newfoundland and Labrador"
	case NWT = "Northwest Territories"
	case NS = "Nova Scotia"
	case Nunavut = "Nunavut"
	case Ontario = "Ontario"
	case PEI = "Prince Edward Island"
	case Quebec = "Quebec"
	case Saskatchewan = "Saskatchewan"
	case Yukon = "Yukon"
}

enum Party: Codable, CaseIterable, Identifiable {
	var id: Self { self }
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
		if let party = Party.allCases.first(where: {
			$0.localizedAbbreviation.caseInsensitiveCompare(name) == .orderedSame ||
			$0.abbreviation.caseInsensitiveCompare(name) == .orderedSame ||
			$0.fullName.caseInsensitiveCompare(name) == .orderedSame ||
			$0.shortName.caseInsensitiveCompare(name) == .orderedSame
		}) {
			return party
		}
		return .independent
	}
}
