//
//  Party.swift
//  epac
//

import Foundation

enum Party: Codable, CaseIterable, Identifiable, Sendable {
	var id: Self { self }

	case conservative
	case liberal
	case newdemocratic
	case bloc
	case green
	case independent

	var abbreviation: String {
		switch self {
		case .conservative: return "CPC"
		case .liberal: return "Lib"
		case .newdemocratic: return "NDP"
		case .bloc: return "BQ"
		case .green: return "GP"
		case .independent: return "Ind"
		}
	}

	var localizedAbbreviation: String {
		switch self {
		case .conservative: return NSLocalizedString("CPC", comment: "")
		case .liberal: return NSLocalizedString("Lib", comment: "")
		case .newdemocratic: return NSLocalizedString("NDP", comment: "")
		case .bloc: return NSLocalizedString("BQ", comment: "")
		case .green: return NSLocalizedString("GP", comment: "")
		case .independent: return NSLocalizedString("Ind", comment: "")
		}
	}

	var fullName: String {
		switch self {
		case .conservative: return NSLocalizedString("Conservative", comment: "")
		case .liberal: return NSLocalizedString("Liberal", comment: "")
		case .newdemocratic: return NSLocalizedString("New Democratic Party", comment: "")
		case .bloc: return NSLocalizedString("Bloc Québécois", comment: "")
		case .green: return NSLocalizedString("Green Party", comment: "")
		case .independent: return NSLocalizedString("Independent", comment: "")
		}
	}

	var shortName: String {
		switch self {
		case .conservative: return NSLocalizedString("Conservative", comment: "")
		case .liberal: return NSLocalizedString("Liberal", comment: "")
		case .newdemocratic: return NSLocalizedString("NDP", comment: "")
		case .bloc: return NSLocalizedString("Bloc Québécois", comment: "")
		case .green: return NSLocalizedString("Green Party", comment: "")
		case .independent: return NSLocalizedString("Independent", comment: "")
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

	var websiteURL: URL? {
		switch self {
		case .liberal: return URL(string: "https://liberal.ca")
		case .conservative: return URL(string: "https://www.conservative.ca")
		case .newdemocratic: return URL(string: "https://www.ndp.ca")
		case .bloc: return URL(string: "https://www.blocquebecois.org")
		case .green: return URL(string: "https://www.greenparty.ca")
		case .independent: return nil
		}
	}
}
