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

typealias SittingCalendar = SchemaV5.SittingCalendar
typealias Hansard = SchemaV5.Hansard
typealias OrderOfBusiness = SchemaV5.OrderOfBusiness
typealias SubjectOfBusiness = SchemaV5.SubjectOfBusiness
typealias ParliamentMember = SchemaV5.ParliamentMember
typealias Speech = SchemaV5.Speech
typealias SpeechMessage = SchemaV5.SpeechMessage
typealias Constituency = SchemaV5.Constituency
typealias TravelClaim = SchemaV5.TravelClaim
typealias TravelExpenditureDetail = SchemaV5.TravelExpenditureDetail
typealias HospitalityExpenditure = SchemaV5.HospitalityExpenditure
typealias ContractExpenditure = SchemaV5.ContractExpenditure
typealias SummaryExpenditure = SchemaV5.SummaryExpenditure
typealias RecordedVote = SchemaV5.RecordedVote
typealias MemberVote = SchemaV5.MemberVote
typealias WrittenQuestion = SchemaV6.WrittenQuestion
typealias FiscalMonitorEntry = SchemaV7.FiscalMonitorEntry
typealias CabinetPosition = SchemaV8.CabinetPosition

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
		var speeches: [SchemaV4.Speech]
		var currentSpeech: SchemaV4.Speech?
		var currentSpeechID: String?
		init(title: String, hansardID: String, speeches: [SchemaV4.Speech] = []) {
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
		var subjects: [SchemaV4.SubjectOfBusiness]
		init(hansardID: String, catchline: String, subjects: [SchemaV4.SubjectOfBusiness] = []) {
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
		var messages: [SchemaV4.SpeechMessage]
		var hansardID: String
		var currentMessage: SchemaV4.SpeechMessage?
		var currentMessageID: String?
		var date: Date
		var length: Int
		var title: String
		init(messages: [SchemaV4.SpeechMessage], hansardID: String, date: Date, title: String) {
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
		var orders: [SchemaV4.OrderOfBusiness]
		init(date: Date, hansardID: String, parliamentNumber: Int, sessionNumber: Int, orders: [SchemaV4.OrderOfBusiness] = []) {
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

		@Relationship(deleteRule: .cascade) var travelClaims: [SchemaV4.TravelClaim] = []
		@Relationship(deleteRule: .cascade) var hospitalityDetails: [SchemaV4.HospitalityExpenditure] = []
		@Relationship(deleteRule: .cascade) var contractDetails: [SchemaV4.ContractExpenditure] = []

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
		var summary: SchemaV4.SummaryExpenditure?
		@Relationship(deleteRule: .cascade) var details: [SchemaV4.TravelExpenditureDetail] = []

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
		var claim: SchemaV4.TravelClaim?

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
		var summary: SchemaV4.SummaryExpenditure?

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
		var summary: SchemaV4.SummaryExpenditure?

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

enum SchemaV5: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(5, 0, 0) }
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
			ContractExpenditure.self,
			RecordedVote.self,
			MemberVote.self
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
		var speeches: [SchemaV5.Speech]
		var currentSpeech: SchemaV5.Speech?
		var currentSpeechID: String?
		init(title: String, hansardID: String, speeches: [SchemaV5.Speech] = []) {
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
		var subjects: [SchemaV5.SubjectOfBusiness]
		init(hansardID: String, catchline: String, subjects: [SchemaV5.SubjectOfBusiness] = []) {
			self.hansardID = hansardID
			self.catchline = catchline
			self.subjects = subjects
		}
	}

	@Model
	final class SpeechMessage {
		#Index<SpeechMessage>([\.lastName])

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
		var messages: [SchemaV5.SpeechMessage]
		var hansardID: String
		var currentMessage: SchemaV5.SpeechMessage?
		var currentMessageID: String?
		var date: Date
		var length: Int
		var title: String
		init(messages: [SchemaV5.SpeechMessage], hansardID: String, date: Date, title: String) {
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
		var orders: [SchemaV5.OrderOfBusiness]
		init(date: Date, hansardID: String, parliamentNumber: Int, sessionNumber: Int, orders: [SchemaV5.OrderOfBusiness] = []) {
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

		@Relationship(deleteRule: .cascade) var travelClaims: [SchemaV5.TravelClaim] = []
		@Relationship(deleteRule: .cascade) var hospitalityDetails: [SchemaV5.HospitalityExpenditure] = []
		@Relationship(deleteRule: .cascade) var contractDetails: [SchemaV5.ContractExpenditure] = []

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
		var summary: SchemaV5.SummaryExpenditure?
		@Relationship(deleteRule: .cascade) var details: [SchemaV5.TravelExpenditureDetail] = []

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
		var claim: SchemaV5.TravelClaim?

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
		var summary: SchemaV5.SummaryExpenditure?

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
		var summary: SchemaV5.SummaryExpenditure?

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

	@Model
	final class RecordedVote {
		@Attribute(.unique) var voteID: Int
		var parliament: Int
		var session: Int
		var number: Int
		var date: Date
		var descriptionEn: String
		var billNumberCode: String
		var yea: Int
		var nay: Int
		var paired: Int
		var resultEn: String
		@Relationship(deleteRule: .cascade, inverse: \SchemaV5.MemberVote.vote) var memberVotes: [SchemaV5.MemberVote] = []
		init(voteID: Int, parliament: Int, session: Int, number: Int, date: Date,
			 descriptionEn: String, billNumberCode: String, yea: Int, nay: Int, paired: Int, resultEn: String) {
			self.voteID = voteID; self.parliament = parliament; self.session = session
			self.number = number; self.date = date; self.descriptionEn = descriptionEn
			self.billNumberCode = billNumberCode; self.yea = yea; self.nay = nay
			self.paired = paired; self.resultEn = resultEn
		}
	}

	@Model
	final class MemberVote {
		var voteID: Int
		var memberID: Int
		var recordedVote: String   // "Yea", "Nay", "Paired", "Abstained"
		var vote: SchemaV5.RecordedVote?
		init(voteID: Int, memberID: Int, recordedVote: String) {
			self.voteID = voteID; self.memberID = memberID; self.recordedVote = recordedVote
		}
	}

}

// MARK: - SchemaV6

enum SchemaV6: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(6, 0, 0) }
	static var models: [any PersistentModel.Type] {
		// All V5 models unchanged + WrittenQuestion
		SchemaV5.models + [WrittenQuestion.self]
	}

	@Model
	final class WrittenQuestion {
		@Attribute(.unique) var questionID: Int
		var memberID: Int
		var parliament: Int
		var session: Int
		var number: Int
		var dateSubmitted: Date
		var subject: String
		var questionTextEn: String
		var statusEn: String
		var responseDate: Date?
		var responseTextEn: String?
		var daysElapsed: Int

		var isOverdue: Bool { responseTextEn == nil && daysElapsed > 45 }

		init(questionID: Int, memberID: Int, parliament: Int, session: Int, number: Int,
			 dateSubmitted: Date, subject: String, questionTextEn: String,
			 statusEn: String, responseDate: Date? = nil, responseTextEn: String? = nil, daysElapsed: Int) {
			self.questionID = questionID
			self.memberID = memberID
			self.parliament = parliament
			self.session = session
			self.number = number
			self.dateSubmitted = dateSubmitted
			self.subject = subject
			self.questionTextEn = questionTextEn
			self.statusEn = statusEn
			self.responseDate = responseDate
			self.responseTextEn = responseTextEn
			self.daysElapsed = daysElapsed
		}
	}
}

// MARK: - SchemaV7

enum SchemaV7: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(7, 0, 0) }
	static var models: [any PersistentModel.Type] {
		// All V6 models unchanged + FiscalMonitorEntry.
		SchemaV6.models + [FiscalMonitorEntry.self]
	}

	@Model
	final class FiscalMonitorEntry: Identifiable {
		@Attribute(.unique) var id: String
		var fiscalYearStart: Int
		var month: Int
		var monthName: String
		var periodDate: Date
		var publicationDate: Date
		var revenueMillions: Double
		var programExpenseMillions: Double
		var publicDebtChargesMillions: Double
		var netActuarialLossesMillions: Double
		var totalSpendingMillions: Double
		var budgetaryBalanceMillions: Double
		var yearToDateBudgetaryBalanceMillions: Double
		var annualBudgetProjectionMillions: Double?
		var sourceTitle: String
		var sourceURL: String

		init(
			fiscalYearStart: Int,
			month: Int,
			monthName: String,
			periodDate: Date,
			publicationDate: Date,
			revenueMillions: Double,
			programExpenseMillions: Double,
			publicDebtChargesMillions: Double,
			netActuarialLossesMillions: Double,
			budgetaryBalanceMillions: Double,
			yearToDateBudgetaryBalanceMillions: Double,
			annualBudgetProjectionMillions: Double?,
			sourceTitle: String,
			sourceURL: String
		) {
			self.id = "\(fiscalYearStart)-\(String(format: "%02d", month))"
			self.fiscalYearStart = fiscalYearStart
			self.month = month
			self.monthName = monthName
			self.periodDate = periodDate
			self.publicationDate = publicationDate
			self.revenueMillions = revenueMillions
			self.programExpenseMillions = programExpenseMillions
			self.publicDebtChargesMillions = publicDebtChargesMillions
			self.netActuarialLossesMillions = netActuarialLossesMillions
			self.totalSpendingMillions = programExpenseMillions + publicDebtChargesMillions + netActuarialLossesMillions
			self.budgetaryBalanceMillions = budgetaryBalanceMillions
			self.yearToDateBudgetaryBalanceMillions = yearToDateBudgetaryBalanceMillions
			self.annualBudgetProjectionMillions = annualBudgetProjectionMillions
			self.sourceTitle = sourceTitle
			self.sourceURL = sourceURL
		}
	}
}

// MARK: - SchemaV8

enum SchemaV8: VersionedSchema {
	static var versionIdentifier: Schema.Version { .init(8, 0, 0) }
	static var models: [any PersistentModel.Type] {
		// All V7 models unchanged + CabinetPosition.
		SchemaV7.models + [CabinetPosition.self]
	}

	@Model
	final class CabinetPosition {
		// Composite identity: the minister's full name uniquely keys the
		// current Cabinet, and re-seeding clears the table first so a member
		// rotating to a new portfolio doesn't leave a stale row behind.
		@Attribute(.unique) var ministerName: String
		var firstName: String
		var lastName: String
		var portfolio: String
		var isPrimeMinister: Bool
		var mandateLetterURL: String?
		var sourceTitle: String
		var sourceURL: String
		var asOfDate: Date

		init(
			ministerName: String,
			firstName: String,
			lastName: String,
			portfolio: String,
			isPrimeMinister: Bool = false,
			mandateLetterURL: String? = nil,
			sourceTitle: String,
			sourceURL: String,
			asOfDate: Date
		) {
			self.ministerName = ministerName
			self.firstName = firstName
			self.lastName = lastName
			self.portfolio = portfolio
			self.isPrimeMinister = isPrimeMinister
			self.mandateLetterURL = mandateLetterURL
			self.sourceTitle = sourceTitle
			self.sourceURL = sourceURL
			self.asOfDate = asOfDate
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

	// Official party website domains. Independents intentionally have no
	// website — Independent is a listing, not a party.
	var websiteURL: URL? {
		switch self {
		case .liberal:        return URL(string: "https://liberal.ca")
		case .conservative:   return URL(string: "https://www.conservative.ca")
		case .newdemocratic:  return URL(string: "https://www.ndp.ca")
		case .bloc:           return URL(string: "https://www.blocquebecois.org")
		case .green:          return URL(string: "https://www.greenparty.ca")
		case .independent:    return nil
		}
	}
}
