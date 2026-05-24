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

private enum AppearanceConstants {
	static let navigationTitleFontSize: CGFloat = 17
	static let messageFontSize: CGFloat = 17
	static let cellTitleFontSize: CGFloat = 16
	static let cellSubtitleFontSize: CGFloat = 12
	static let messageSpeakerNameFontSize: CGFloat = 14
	static let messageRidingNameFontSize: CGFloat = 14
	static let rgbMinimumComponent = 0
	static let rgbMaximumComponent = 255
	static let rgbDivisor: CGFloat = 255
	static let rgbAlpha: CGFloat = 1
	static let redComponentShift = 16
	static let greenComponentShift = 8
	static let rgbComponentMask = 0xFF
}

class Appearance {
	@MainActor
	class func setup() {
		UINavigationBar.appearance().titleTextAttributes = [
			.font: UIFont(name: "CooperHewitt-Semibold", size: AppearanceConstants.navigationTitleFontSize)!
		]
		UINavigationBar.appearance().tintColor = UIColor.black
	}
}

extension Font {
	static let messageFont: UIFont = UIFont(name: "CooperHewitt-Book", size: AppearanceConstants.messageFontSize)!
	static let cellTitleFont: UIFont = UIFont(name: "CooperHewitt-Semibold", size: AppearanceConstants.cellTitleFontSize)!
	static let cellSubtitleFont: UIFont = UIFont(name: "CooperHewitt-Book", size: AppearanceConstants.cellSubtitleFontSize)!
	static let cellBoldSubTitleFont: UIFont = UIFont(name: "CooperHewitt-Semibold", size: AppearanceConstants.cellSubtitleFontSize)!
	static let messageSpeakerNameFont: UIFont = UIFont(name: "CooperHewitt-Semibold", size: AppearanceConstants.messageSpeakerNameFontSize)!
	static let messageRidingNameFont: UIFont = UIFont(name: "CooperHewitt-Book", size: AppearanceConstants.messageRidingNameFontSize)!
	static let messagePartyNameFont: UIFont = UIFont(name: "CooperHewitt-Book", size: AppearanceConstants.cellSubtitleFontSize)!
}

extension View {
	/// Applies a glass-style header background: `glassEffect()` on iOS 26+,
	/// `.ultraThinMaterial` on earlier releases.
	@ViewBuilder
	func glassHeaderStyle() -> some View {
		// glassEffect() requires Xcode 26 (Swift 6.2+). Fall back to
		// ultraThinMaterial when building with an earlier toolchain.
#if swift(>=6.2)
		if #available(iOS 26.0, *) {
			self.glassEffect()
		} else {
			self.background(.ultraThinMaterial)
		}
#else
		self.background(.ultraThinMaterial)
#endif
	}
}

extension UIColor {
	convenience init(red: Int, green: Int, blue: Int) {
		assert(red >= AppearanceConstants.rgbMinimumComponent && red <= AppearanceConstants.rgbMaximumComponent, "Invalid red component")
		assert(green >= AppearanceConstants.rgbMinimumComponent && green <= AppearanceConstants.rgbMaximumComponent, "Invalid green component")
		assert(blue >= AppearanceConstants.rgbMinimumComponent && blue <= AppearanceConstants.rgbMaximumComponent, "Invalid blue component")

		self.init(
			red: CGFloat(red) / AppearanceConstants.rgbDivisor,
			green: CGFloat(green) / AppearanceConstants.rgbDivisor,
			blue: CGFloat(blue) / AppearanceConstants.rgbDivisor,
			alpha: AppearanceConstants.rgbAlpha
		)
	}

	convenience init(rgb: Int) {
		self.init(
			red: (rgb >> AppearanceConstants.redComponentShift) & AppearanceConstants.rgbComponentMask,
			green: (rgb >> AppearanceConstants.greenComponentShift) & AppearanceConstants.rgbComponentMask,
			blue: rgb & AppearanceConstants.rgbComponentMask
		)
	}
}
