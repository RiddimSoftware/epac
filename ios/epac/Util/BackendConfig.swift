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

    /// Production AWS API Gateway base URL. All builds use this by default.
    static let productionBaseURL = URL(string: "https://smun5g2szc.execute-api.us-east-1.amazonaws.com/production")!

    /// Effective backend base URL for this run. Runtime environment overrides
    /// win first for local testing; otherwise the Info.plist build setting
    /// selects Debug staging or Release production.
    let baseURL: URL

    init() {
        self.baseURL = Self.resolvedBaseURL()
    }

    private static func resolvedBaseURL() -> URL {
        if let override = validURL(ProcessInfo.processInfo.environment["BACKEND_BASE_URL"]) {
            return override
        }
        if let configured = validURL(Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String) {
            return configured
        }
        return productionBaseURL
    }

    private static func validURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              let url = URL(string: trimmed),
              url.scheme == "https" else { return nil }
        return url
    }
}
