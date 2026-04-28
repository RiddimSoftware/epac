//
//  BackendConfig.swift
//  epac
//
//  Single source of truth for the backend base URL. Services in `Util/` should
//  read `BackendConfig.shared.baseURL` rather than hardcoding their own host,
//  so swapping production for staging is a one-touch change.
//
//  Override at runtime by setting the `BACKEND_BASE_URL` env var in the active
//  Xcode scheme: Edit Scheme → Run → Arguments → Environment Variables. This is
//  how a TestFlight scheme can be pointed at the staging environment once it
//  exists (tracked under EPAC-156 Phase 2).
//

import Foundation

struct BackendConfig {
    static let shared = BackendConfig()

    /// Production AWS API Gateway base. The default for both Debug and Release
    /// schemes today; will become the Release-only default once Phase 2 lands
    /// and a separate staging URL is wired into Debug via xcconfig.
    static let productionBaseURL = URL(string: "https://smun5g2szc.execute-api.us-east-1.amazonaws.com/production")!

    /// Effective backend base URL for this run. Honours a `BACKEND_BASE_URL`
    /// environment-variable override if one is set on the scheme, otherwise
    /// falls back to `productionBaseURL`.
    let baseURL: URL

    init() {
        if let override = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"],
           let overrideURL = URL(string: override),
           overrideURL.scheme == "https" {
            self.baseURL = overrideURL
        } else {
            self.baseURL = Self.productionBaseURL
        }
    }
}
