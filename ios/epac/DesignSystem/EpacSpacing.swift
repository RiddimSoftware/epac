import CoreFoundation

// 4-pt base grid. Prefer these constants over raw literals in padding
// and spacing modifiers so a single change re-calibrates the whole app.

enum EpacSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
