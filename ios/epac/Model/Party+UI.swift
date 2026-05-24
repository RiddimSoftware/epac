//
//  Party+UI.swift
//  epac
//

import UIKit

extension Party {
	var image: UIImage? {
		UIImage(named: abbreviation)
	}

	// swiftlint:disable no_magic_numbers
	var colour: UIColor {
		switch self {
		case .conservative: return UIColor(rgb: 0x1A4782)
		case .liberal: return UIColor(rgb: 0xd71920)
		case .newdemocratic: return UIColor(rgb: 0xF37021)
		case .bloc: return UIColor(rgb: 0x33B2CC)
		case .green: return UIColor(rgb: 0x3D9B35)
		case .independent: return UIColor.darkText
		}
	}
	// swiftlint:enable no_magic_numbers
}
