import SwiftUI
import UIKit

// MARK: - Text

extension Color {
    static let epacText = EpacTextPalette()
    static let epacSurface = EpacSurfacePalette()
    static let epacBrand = EpacBrandPalette()
    static let epacStatus = EpacStatusPalette()
}

struct EpacTextPalette {
    // Resolved by the system; call sites do not need to inspect colorScheme.
    let primary: Color = Color(uiColor: .label)
    let secondary: Color = Color(uiColor: .secondaryLabel)
    let tertiary: Color = Color(uiColor: .tertiaryLabel)
    let accent: Color = .accentColor
    let onAccent: Color = Color(uiColor: .white)
}

// MARK: - Surface

struct EpacSurfacePalette {
    let primary: Color = Color(uiColor: .systemBackground)
    let elevated: Color = Color(uiColor: .secondarySystemBackground)
    let grouped: Color = Color(uiColor: .systemGroupedBackground)
    let groupedElevated: Color = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Brand

struct EpacBrandPalette {
    let accent: Color = .accentColor
    let accentMuted: Color = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemBlue.withAlphaComponent(CGFloat(EpacOpacity.tintStrong))
            : UIColor.systemBlue.withAlphaComponent(CGFloat(EpacOpacity.tint))
    })
    // Civic role colors: used for vote outcomes and MP party indicators.
    let positive: Color = Color(uiColor: .systemGreen)
    let negative: Color = Color(uiColor: .systemRed)
    let neutral: Color = Color(uiColor: .systemGray)
}

// MARK: - Status

struct EpacStatusPalette {
    let success: Color = Color(uiColor: .systemGreen)
    let warning: Color = Color(uiColor: .systemOrange)
    let destructive: Color = Color(uiColor: .systemRed)
    let info: Color = Color(uiColor: .systemBlue)
}
