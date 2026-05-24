//
//  DesignTokens.swift
//  epac
//
//  Single source of truth for all design tokens: party colours, semantic
//  surface colours, typography scale, and vote/bill status colours.
//  Views must not hard-code UIColor.system* or party.colour directly —
//  use these tokens instead.
//

import SwiftUI
import UIKit

private enum DesignTokenConstants {
    static let partyDarkModeLightening: CGFloat = 0.30
    static let partySubtleAlpha: CGFloat = 0.15
    static let saturationCompensationRatio: CGFloat = 0.3
    static let appCardCornerRadius: CGFloat = 12
}

// MARK: — Party colours

extension Color {
    /// Canonical party colour — dark-mode adaptive.
    /// In dark mode the colour is lightened (HSB) for contrast on dark surfaces.
    static func party(_ party: Party) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? party.colour.lightened(by: DesignTokenConstants.partyDarkModeLightening)
                : party.colour
        })
    }

    /// Subtle tinted background for badges, chips, and avatar placeholders.
    /// 15% opacity in both modes — visible but unobtrusive over system backgrounds.
    static func partySubtle(_ party: Party) -> Color {
        Color(uiColor: party.colour.withAlphaComponent(DesignTokenConstants.partySubtleAlpha))
    }
}

// MARK: — UIColor utilities

extension UIColor {
    /// Increases perceived brightness in HSB space.
    /// Saturation is slightly reduced to compensate for hue wash-out at high brightness.
    /// Achromatic colors (s = 0) brighten without hue shift.
    func lightened(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h,
                       saturation: max(0, s - amount * DesignTokenConstants.saturationCompensationRatio),
                       brightness: min(1, b + amount),
                       alpha: a)
    }
}

// MARK: — Semantic surface colours

extension Color {
    /// Equivalent to UIColor.secondarySystemBackground — card/sheet surfaces.
    static let appSurface = Color(UIColor.secondarySystemBackground)
    /// Equivalent to UIColor.tertiarySystemBackground — nested surfaces.
    static let appSurfaceSecondary = Color(UIColor.tertiarySystemBackground)
    /// Equivalent to UIColor.systemBackground — primary background.
    static let appBackground = Color(UIColor.systemBackground)
    /// Equivalent to UIColor.separator — dividers and borders.
    static let appDivider = Color(UIColor.separator)
    /// Tinted destructive colour for negative vote indicators, errors.
    static let appDestructive = Color(UIColor.systemRed)
    /// Positive / passing colour.
    static let appPositive = Color(UIColor.systemGreen)
    /// Warning / in-progress colour.
    static let appWarning = Color(UIColor.systemOrange)
    /// Neutral colour for unknown/abstained states.
    static let appNeutral = Color(UIColor.systemGray3)
}

// MARK: — Typography scale

extension Font {
    /// Largest display text — page titles. Maps to .largeTitle.
    static let appDisplay: Font = .largeTitle.weight(.bold)
    /// Section headers and card titles. Maps to .title3.
    static let appTitle: Font = .title3.weight(.semibold)
    /// Primary readable text. Maps to .body.
    static let appBody: Font = .body
    /// Secondary metadata. Maps to .subheadline.
    static let appSubheadline: Font = .subheadline
    /// Smallest visible metadata — dates, bylines. Maps to .caption.
    static let appCaption: Font = .caption
    /// Badges, pills, status labels — bold at small size.
    static let appLabel: Font = .caption2.weight(.semibold)
}

// MARK: — Vote ballot colours
// Used consistently across MemberVotingHistoryView, VoteDetailView, BillDetailView.

extension Color {
    static func ballot(_ recordedVote: String) -> Color {
        switch recordedVote.lowercased() {
        case "yea":    return .appPositive
        case "nay":    return .appDestructive
        case "paired": return .appWarning
        default:       return .appNeutral
        }
    }
}

// MARK: — View modifiers

extension View {
    /// Standard epac card: secondary system background + cornerRadius 12.
    /// Apply AFTER any inner `.background()` modifiers.
    func epacCard() -> some View {
        self.background(Color.appSurface).cornerRadius(DesignTokenConstants.appCardCornerRadius)
    }
}

// MARK: — Bill status colours

extension Color {
    static func billStatus(_ status: BillStatus) -> Color {
        switch status {
        case .inProgress:  return Color(UIColor.systemBlue)
        case .royalAssent: return Color(UIColor.systemPurple)
        case .defeated:    return .appDestructive
        case .unknown:     return .appNeutral
        }
    }
}
