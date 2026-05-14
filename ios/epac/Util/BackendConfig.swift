//
//  BackendConfig.swift
//  epac
//
//  Single source of truth for the backend base URL. Services in `Util/` read
//  `BackendConfig.shared.baseURL` rather than hardcoding their own host.
//

import Foundation

struct BackendConfig {
    static let shared = BackendConfig()

    /// Production custom domain base URL.
    static let productionBaseURL = URL(string: "https://api.epac.riddimsoftware.com")!

    /// Effective backend base URL for this run. Runtime environment overrides
    /// win first for local testing; otherwise the Info.plist build setting
    /// selects Debug staging or Release production.
    let baseURL: URL

    init() {
        self.baseURL = Self.resolvedBaseURL(
            envValue: ProcessInfo.processInfo.environment["BACKEND_BASE_URL"],
            plistValue: Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String
        )
    }

    /// Testable initializer: accepts the two resolution inputs directly so
    /// unit tests don't need a real bundle or process environment.
    init(envValue: String?, plistValue: String?) {
        self.baseURL = Self.resolvedBaseURL(envValue: envValue, plistValue: plistValue)
    }

    static func resolvedBaseURL(envValue: String?, plistValue: String?) -> URL {
        if let override = validURL(envValue) {
            return override
        }
        if let configured = validURL(plistValue) {
            return configured
        }
        return productionBaseURL
    }

    static func validURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              let url = URL(string: trimmed),
              url.scheme == "https" else { return nil }
        return url
    }
}
