//
//  Calendar.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftData
import Foundation
import UIKit

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
final class ParliamentMember {
	var name:           String
	var lastName:       String?
	var firstName:      String?
	var photoURL:       URL?
	var websiteURL:     URL?
	var riding:         String
	var party:          Party
	init(name: String, lastName: String? = nil, firstName: String? = nil, photoURL: URL? = nil, websiteURL: URL? = nil, riding: String, party: Party) {
		self.name = name
		self.lastName = lastName
		self.firstName = firstName
		self.photoURL = photoURL
		self.websiteURL = websiteURL
		self.riding = riding
		self.party = party
	}
}

@Model
final class SubjectOfBusiness {
	var title: String
	var hansardID: String?
	var speeches: [Speech]
	init(title: String, hansardID: String?, speeches: [Speech] = []) {
		self.title = title.trimmingCharacters(in: CharacterSet.whitespaces)
		self.hansardID = hansardID
		self.speeches = speeches
	}
}

@Model
final class OrderOfBusiness {
	var hansardID: String?
	var catchline: String
	var subjects: [SubjectOfBusiness]
	init(hansardID: String?, catchline: String, subjects: [SubjectOfBusiness] = []) {
		self.hansardID = hansardID
		self.catchline = catchline
		self.subjects = subjects
	}
}

@Model
// <ParaText>
final class SpeechMessage {
	var speaker: ParliamentMember
	var hansardID: String?
	var content: String
	var timestamp: Date
	init(speaker: ParliamentMember, hansardID: String?, content: String, timestamp: Date) {
		self.speaker = speaker
		self.hansardID = hansardID
		self.content = content
		self.timestamp = timestamp
	}
}

@Model
// <Intervention><Content>
final class Speech {
	var messages: [SpeechMessage]
	var hansardID: String?
	var currentMessage: SpeechMessage?
	var date: Date
	var length: Int
	var title: String
	init(messages: [SpeechMessage], hansardID: String?, currentMessage: SpeechMessage? = nil, date: Date, length: Int, title: String) {
		self.messages = messages
		self.hansardID = hansardID
		self.currentMessage = currentMessage
		self.date = date
		self.length = length
		self.title = title
	}
}

//@Model
//final class Debate {
//	var speeches: [Speech]
//	var speakers: [Member]
//}

enum Party: Codable {
		case conservative
		case liberal
		case newdemocratic
		case bloc
		case green
		case other

		var abbreviation: String {
				switch self {
				case .conservative:     return "CPC"
				case .liberal:          return "Lib"
				case .newdemocratic:    return "NDP"
				case .bloc:             return "BQ"
				case .green:            return "GP"
				case .other:            return ""
				}
		}

		var localizedAbbreviation: String {
				switch self {
				case .conservative:     return NSLocalizedString("CPC", comment: "")
				case .liberal:          return NSLocalizedString("Lib", comment: "")
				case .newdemocratic:    return NSLocalizedString("NDP", comment: "")
				case .bloc:             return NSLocalizedString("BQ", comment: "")
				case .green:            return NSLocalizedString("GP", comment: "")
				case .other:            return ""
				}
		}

		var fullName: String {
				switch self {
				case .conservative:     return NSLocalizedString("Conservative", comment: "")
				case .liberal:          return NSLocalizedString("Liberal", comment: "")
				case .newdemocratic:    return NSLocalizedString("New Democratic Party", comment: "")
				case .bloc:             return NSLocalizedString("Bloc Québécois", comment: "")
				case .green:            return NSLocalizedString("Green Party", comment: "")
				case .other:            return ""
				}
		}

		var colour: UIColor {
				switch self {
				case .conservative:     return UIColor(rgb: 0x1A4782)
				case .liberal:          return UIColor(rgb: 0xd71920)
				case .newdemocratic:    return UIColor(rgb: 0xF37021)
				case .bloc:             return UIColor(rgb: 0x33B2CC)
				case .green:            return UIColor(rgb: 0x3D9B35)
				case .other:            return UIColor.darkText
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
				return .other
		}
}
