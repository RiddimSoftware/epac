import CoreFoundation

// Frame dimensions, corner radii, and indicator sizes for marketing and
// App Store presentation views (AppPreviewVideoView, AppStoreScreenshotShowcaseView).
// These values are specific to phone-mockup layouts and are not part of the
// general 4-pt grid.

enum EpacMedia {
    // App preview phone frame (AppPreviewVideoView)
    static let previewPhoneWidth: CGFloat = 338
    static let previewPhoneHeight: CGFloat = 650
    static let previewPhoneCornerRadius: CGFloat = 34

    // App Store screenshot phone frame (AppStoreScreenshotShowcaseView)
    static let screenshotPhoneMinHeight: CGFloat = 560
    static let screenshotPhoneCornerRadius: CGFloat = 28

    // Page indicator dots
    static let pageDotActiveWidth: CGFloat = 26
    static let pageDotInactiveWidth: CGFloat = 8
    static let pageDotHeight: CGFloat = 8
}
