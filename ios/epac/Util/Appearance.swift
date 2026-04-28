//
//  Appearance.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-04.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import SwiftUI
import UIKit

class Appearance {
	@MainActor
	class func setup() {
		UINavigationBar.appearance().titleTextAttributes = [.font: UIFont(name: "CooperHewitt-Semibold", size: 17)!]
		UINavigationBar.appearance().tintColor = UIColor.black
	}
}

extension Font {
	static let messageFont: UIFont = UIFont(name: "CooperHewitt-Book", size: 17)!
	static let cellTitleFont: UIFont = UIFont(name: "CooperHewitt-Semibold", size: 16)!
	static let cellSubtitleFont: UIFont = UIFont(name: "CooperHewitt-Book", size: 12)!
	static let cellBoldSubTitleFont: UIFont = UIFont(name: "CooperHewitt-Semibold", size: 12)!
	static let messageSpeakerNameFont: UIFont = UIFont(name: "CooperHewitt-Semibold", size: 14)!
	static let messageRidingNameFont: UIFont = UIFont(name: "CooperHewitt-Book", size: 14)!
	static let messagePartyNameFont: UIFont = UIFont(name: "CooperHewitt-Book", size: 12)!
}

extension View {
	/// Applies a glass-style header background: `glassEffect()` on iOS 26+,
	/// `.ultraThinMaterial` on earlier releases.
	@ViewBuilder
	func glassHeaderStyle() -> some View {
		if #available(iOS 26.0, *) {
			self.glassEffect()
		} else {
			self.background(.ultraThinMaterial)
		}
	}
}

extension UIColor {
	convenience init(red: Int, green: Int, blue: Int) {
		assert(red >= 0 && red <= 255, "Invalid red component")
		assert(green >= 0 && green <= 255, "Invalid green component")
		assert(blue >= 0 && blue <= 255, "Invalid blue component")

		self.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1.0)
	}

	convenience init(rgb: Int) {
		self.init(
			red: (rgb >> 16) & 0xFF,
			green: (rgb >> 8) & 0xFF,
			blue: rgb & 0xFF
		)
	}
}
