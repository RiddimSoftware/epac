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
	static let rgbMinimumComponent = 0
	static let rgbMaximumComponent = 255
	static let rgbDivisor: CGFloat = 255
	static let rgbAlpha: CGFloat = 1
	static let redComponentShift = 16
	static let greenComponentShift = 8
	static let rgbComponentMask = 0xFF
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
