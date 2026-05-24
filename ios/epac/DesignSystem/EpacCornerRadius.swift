import CoreFoundation

// Radius scale for `clipShape(RoundedRectangle(...))` and `cornerRadius(...)` modifiers.
// Values follow the same 4-pt grid as EpacSpacing. `full` produces a pill shape.

enum EpacCornerRadius {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999 // pill / capsule shape
}
