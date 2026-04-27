//
//  DesignSystem.swift
//  epac
//

import SwiftUI

// MARK: - Party colour tokens

extension Party {
	/// SwiftUI-native color, dark-mode adaptive.
	/// Use this in SwiftUI views instead of `Color(uiColor: party.colour)`.
	var swiftUIColor: Color {
		Color(uiColor: adaptiveUIColor)
	}

	/// Subtle tinted background for badges, chips, and pill backgrounds.
	/// Equivalent to the existing `.opacity(0.1)` pattern, but centralized
	/// and slightly higher opacity in dark mode for legibility.
	var subtleBackground: Color {
		Color(uiColor: UIColor { trait in
			trait.userInterfaceStyle == .dark
				? self.colour.withAlphaComponent(0.20)
				: self.colour.withAlphaComponent(0.10)
		})
	}

	/// Adaptive `UIColor` — same hue as `colour` in light mode,
	/// lightened by 30% in dark mode for contrast on dark backgrounds.
	var adaptiveUIColor: UIColor {
		UIColor { [self] trait in
			if trait.userInterfaceStyle == .dark {
				return self.colour.lightened(by: 0.30)
			}
			return self.colour
		}
	}
}

// MARK: - UIColor helpers

extension UIColor {
	/// Returns the color with all RGB channels increased by `amount` (0…1).
	func lightened(by amount: CGFloat) -> UIColor {
		var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		getHue(&h, saturation: &s, brightness: &b, alpha: &a)
		return UIColor(hue: h, saturation: max(0, s - amount * 0.3),
		               brightness: min(1, b + amount), alpha: a)
	}
}

// MARK: - Typography scale

extension Font {
	/// Primary display font — `.title2`, rounded design.
	static var epacDisplay: Font { .system(.title2, design: .rounded) }

	/// Section heading — `.headline`, rounded design.
	static var epacHeadline: Font { .system(.headline, design: .rounded) }

	/// Standard body text — `.body`, rounded design.
	static var epacBody: Font { .system(.body, design: .rounded) }

	/// Secondary label — `.subheadline`, rounded design.
	static var epacSubheadline: Font { .system(.subheadline, design: .rounded) }

	/// Caption for metadata rows — `.caption`, rounded design.
	static var epacCaption: Font { .system(.caption, design: .rounded) }

	/// Small caption (riding, province) — `.caption2`, rounded design.
	static var epacCaption2: Font { .system(.caption2, design: .rounded) }
}

// MARK: - Semantic colors

extension Color {
	/// Tinted background for cards and grouped list sections.
	static var epacGroupedBackground: Color { Color(.systemGroupedBackground) }

	/// Secondary grouped background (inset List cells).
	static var epacSecondaryBackground: Color { Color(.secondarySystemGroupedBackground) }

	/// Primary text — adapts to light/dark automatically.
	static var epacPrimary: Color { Color(.label) }

	/// Secondary text — muted, adapts automatically.
	static var epacSecondary: Color { Color(.secondaryLabel) }

	/// Separator line color.
	static var epacSeparator: Color { Color(.separator) }
}

// MARK: - View modifiers

extension View {
	/// Applies the standard epac rounded-card style:
	/// secondary background, corner radius 12, no padding (caller adds padding).
	func epacCard() -> some View {
		self
			.background(Color.epacSecondaryBackground)
			.cornerRadius(12)
	}
}
