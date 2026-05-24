import Foundation

// Opacity constants for overlays, fills, disabled states, and borders.
// Used with `.opacity(EpacOpacity.disabled)` (SwiftUI) and
// `UIColor.withAlphaComponent(CGFloat(EpacOpacity.tint))` (UIKit).

enum EpacOpacity {
    // Semantic role values
    static let overlay: Double = 0.5    // modal overlays, dimming backgrounds
    static let disabled: Double = 0.3   // disabled controls, inactive states
    static let subtle: Double = 0.7     // secondary visual weight
    static let dim: Double = 0.35       // dimmed indicators (e.g. inactive page dots)

    // Tint fill values (for coloured backgrounds behind icons / avatars)
    static let tint: Double = 0.12          // light-mode accent tint fills
    static let tintMedium: Double = 0.16    // selection highlight fills
    static let avatarTint: Double = 0.18    // avatar / monogram background fills
    static let tintStrong: Double = 0.20    // dark-mode accent tint fills

    // Border and shadow values
    static let border: Double = 0.45    // translucent borders and overlays
    static let shadow: Double = 0.32    // standard drop shadows
}
