import SwiftUI

// Named animation durations and preset Animation values.
// Use the Double constants in `.animation(.easeInOut(duration: EpacAnimation.standard), ...)`;
// use the preset Animation values in `withAnimation(EpacAnimation.easeInOut) { ... }`.

enum EpacAnimation {
    // Duration constants (seconds)
    static let fast: Double = 0.15
    static let standard: Double = 0.3
    static let slow: Double = 0.5

    // Preset SwiftUI animations
    static var easeInOut: Animation { .easeInOut(duration: standard) }
    static var easeInOutFast: Animation { .easeInOut(duration: fast) }
    static var easeInOutSlow: Animation { .easeInOut(duration: slow) }
}
