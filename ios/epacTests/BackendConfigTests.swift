@testable import epac
import Foundation
import Testing

struct BackendConfigTests {
    // MARK: - Debug / Release config values

    @Test func debugXcconfigPointsAtStagingURL() {
        // Debug.xcconfig sets BACKEND_BASE_URL to the staging host.
        // The plist value after xcconfig substitution is the staging URL.
        let config = BackendConfig(
            envValue: nil,
            plistValue: "https://staging-api.epac.riddimsoftware.com"
        )
        #expect(config.baseURL == URL(string: "https://staging-api.epac.riddimsoftware.com")!)
    }

    @Test func releaseXcconfigPointsAtProductionURL() {
        let config = BackendConfig(
            envValue: nil,
            plistValue: "https://api.epac.riddimsoftware.com"
        )
        #expect(config.baseURL == BackendConfig.productionBaseURL)
    }

    // MARK: - Fallback behaviour

    @Test func missingPlistValueFallsBackToProduction() {
        // When Debug.xcconfig is absent the plist substitution produces an
        // empty string, so BackendConfig must fall back to the production URL.
        let config = BackendConfig(envValue: nil, plistValue: nil)
        #expect(config.baseURL == BackendConfig.productionBaseURL)
    }

    @Test func unresolvedXcconfigVariableIsRejected() {
        // If BACKEND_BASE_URL is undefined in a config file, Xcode substitutes
        // the raw variable reference `$(BACKEND_BASE_URL)` into the plist.
        // validURL must reject that string so we fall back to production.
        let config = BackendConfig(envValue: nil, plistValue: "$(BACKEND_BASE_URL)")
        #expect(config.baseURL == BackendConfig.productionBaseURL)
    }

    @Test func emptyPlistValueFallsBackToProduction() {
        let config = BackendConfig(envValue: nil, plistValue: "")
        #expect(config.baseURL == BackendConfig.productionBaseURL)
    }

    // MARK: - Runtime env var override

    @Test func envVarOverrideWinsOverPlistValue() {
        let override = "https://override.example.com"
        let config = BackendConfig(
            envValue: override,
            plistValue: "https://staging-api.epac.riddimsoftware.com"
        )
        #expect(config.baseURL == URL(string: override)!)
    }

    @Test func invalidEnvVarFallsThroughToPlistValue() {
        let config = BackendConfig(
            envValue: "http://insecure.example.com",
            plistValue: "https://staging-api.epac.riddimsoftware.com"
        )
        #expect(config.baseURL == URL(string: "https://staging-api.epac.riddimsoftware.com")!)
    }

    // MARK: - validURL

    @Test func httpURLIsRejected() {
        #expect(BackendConfig.validURL("http://api.epac.riddimsoftware.com") == nil)
    }

    @Test func httpsURLIsAccepted() {
        #expect(BackendConfig.validURL("https://api.epac.riddimsoftware.com") != nil)
    }

    @Test func nilInputReturnsNil() {
        #expect(BackendConfig.validURL(nil) == nil)
    }

    @Test func whitespaceOnlyInputReturnsNil() {
        #expect(BackendConfig.validURL("   ") == nil)
    }

    @Test func xcconfigVariableReferenceReturnsNil() {
        #expect(BackendConfig.validURL("$(BACKEND_BASE_URL)") == nil)
    }
}
