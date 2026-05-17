import Foundation

enum AppEnvironment {
    static let appPreviewPostalCode = "M5H 2N2"

    static var isAppStoreScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-AppStoreScreenshots")
    }

    static var isAppPreviewMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--app-preview-mode") ||
        ProcessInfo.processInfo.arguments.contains("-AppPreviewVideo") ||
        ProcessInfo.processInfo.environment["EPAC_APP_PREVIEW_MODE"] == "1"
    }

    static var isAppPreviewManualSequence: Bool {
        ProcessInfo.processInfo.arguments.contains("--app-preview-manual-sequence") ||
        ProcessInfo.processInfo.environment["EPAC_APP_PREVIEW_MANUAL_SEQUENCE"] == "1"
    }

    static var isEvidenceCaptureMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--evidence-mode") ||
        ProcessInfo.processInfo.environment["EPAC_EVIDENCE_MODE"] == "1" ||
        debugOnThisDayFixtureIsPresent
    }

    static var isMarketingCaptureMode: Bool {
        isAppStoreScreenshotMode || isAppPreviewMode || isEvidenceCaptureMode
    }

    private static var debugOnThisDayFixtureIsPresent: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--on-this-day-fixture-json") ||
        ProcessInfo.processInfo.environment["EPAC_DEBUG_ON_THIS_DAY_FIXTURE_JSON"] != nil
        #else
        false
        #endif
    }
}
