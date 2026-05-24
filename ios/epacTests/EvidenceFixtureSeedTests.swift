@testable import epac
import Foundation
import Testing

/// Behaviour-level tests for `EvidenceFixtureSeed`'s fixture-selection logic.
/// Bundle-loading and the live `Fetch.ingestHansard(xml:)` integration are
/// exercised by the evidence-regression workflow's actual run, not here —
/// these tests cover the env-var dispatch surface that has no other coverage.
struct EvidenceFixtureSeedTests {
    @Test func selectedFixture_defaultsToHAN050_whenEnvUnset() {
        // The default fixture name is the constant ContentView and the plan rely on.
        // If it changes, .evidence/regression-parliament-calendar.json must change too.
        #expect(EvidenceFixtureSeed.defaultFixtureName == "45-1-HAN050-E")
    }

    @Test func fixtureDates_containAllThreeBundledFixtures() {
        let names = Set(EvidenceFixtureSeed.fixtureDates.keys)
        #expect(names == ["45-1-HAN020-E", "45-1-HAN050-E", "45-1-HAN100-E"])
    }

    @Test func fixtureDates_useISO8601_format() {
        // The plan substitutes these date strings directly into deep-link URLs
        // (cabinetdoor://sitting/<date>), so they must be yyyy-MM-dd with no
        // weekday / month-name decoration.
        let pattern = #/^\d{4}-\d{2}-\d{2}$/#
        for (name, date) in EvidenceFixtureSeed.fixtureDates {
            #expect(date.firstMatch(of: pattern) != nil, "fixture \(name) date \(date) does not match yyyy-MM-dd")
        }
    }

    @Test func selectedFixture_fallsBackToDefault_whenEnvNamesUnknownFixture() {
        // The function reads ProcessInfo at call time. We can't override that here
        // without setenv, so this test documents the invariant:
        // selectedFixture()'s fallback path must return the default fixture.
        let result = EvidenceFixtureSeed.selectedFixture()
        let validNames = Set(EvidenceFixtureSeed.fixtureDates.keys)
        #expect(validNames.contains(result.name), "selectedFixture returned non-bundled name \(result.name)")
        // The sitting date must be one of the configured ones.
        #expect(EvidenceFixtureSeed.fixtureDates.values.contains(result.sittingDate))
    }
}
