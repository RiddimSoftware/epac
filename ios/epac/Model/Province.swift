//
//  Province.swift
//  epac
//

import Foundation

enum Province: String, Codable, CaseIterable, Identifiable, Sendable {
	var id: Self { self }

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
}
