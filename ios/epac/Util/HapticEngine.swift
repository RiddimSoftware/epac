import UIKit

/// Thin wrapper around UIImpactFeedbackGenerator and UINotificationFeedbackGenerator.
/// All methods are no-ops when the user has enabled Reduce Motion in Accessibility settings.
@MainActor
enum HapticEngine {
    /// Light tap — used for lightweight commitments (following a member or bill).
    static func light() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap — used for meaningful actions (sending a message to an MP).
    static func medium() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Soft tap — used for drawing attention (tapping a notification banner).
    static func soft() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Rigid tap — used for deliberate gestures (long-press to share).
    static func rigid() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// Success notification — used for milestones (completing postal code onboarding).
    static func success() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
