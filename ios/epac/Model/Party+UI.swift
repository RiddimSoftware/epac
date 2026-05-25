//
//  Party+UI.swift
//  epac
//

import UIKit

private enum PartyColourValue {
	static let conservativeRGB = 0x1A4782
	static let saskatchewanPartyRGB = 0x1D7F3F
	static let liberalRGB = 0xd71920
	static let newDemocraticRGB = 0xF37021
	static let blocRGB = 0x33B2CC
	static let greenRGB = 0x3D9B35
}

extension Party {
	var image: UIImage? {
		UIImage(named: abbreviation)
	}

	var colour: UIColor {
		switch self {
		case .conservative: return UIColor(rgb: PartyColourValue.conservativeRGB)
		case .saskatchewanParty: return UIColor(rgb: PartyColourValue.saskatchewanPartyRGB)
		case .liberal: return UIColor(rgb: PartyColourValue.liberalRGB)
		case .newdemocratic: return UIColor(rgb: PartyColourValue.newDemocraticRGB)
		case .bloc: return UIColor(rgb: PartyColourValue.blocRGB)
		case .green: return UIColor(rgb: PartyColourValue.greenRGB)
		case .independent: return UIColor.darkText
		}
	}
}
