import Foundation

/// Seeds the in-memory SwiftData store with a real Hansard XML when the app launches
/// under `EPAC_EVIDENCE_MODE=1`. Three Hansards are bundled in the app under
/// `Resources/EvidenceFixtures/`, each a real XML downloaded from ourcommons.ca and
/// spaced across the past 12 months. The active fixture is selected via the
/// `EPAC_EVIDENCE_FIXTURE` env var; if unset (or unrecognized), `defaultFixtureName`
/// is used. Within a single evidence-capture run, both the before- and after-revision
/// launches receive the same env value, so seeded state is identical across phases.
///
/// The seed calls `Fetch.ingestHansard(xml:)` directly — the same parse-and-persist
/// code path `Fetch.downloadHansard` uses after its URLSession download — so the
/// seed itself exercises `XMLBro.parseXML`, `HansardSpeakerParser`, and the
/// `Hansard` SwiftData mapping. A regression in any of those would surface as a
/// seed failure (empty Parliament tab) before the evidence plan's deep links fire.
enum EvidenceFixtureSeed {
    /// Resource name (without `.XML` extension) of the default fixture loaded when
    /// the `EPAC_EVIDENCE_FIXTURE` env var is unset or unknown. November 2025 sits
    /// roughly in the middle of the bundled past-12-month range, making it the
    /// most representative single choice.
    static let defaultFixtureName = "45-1-HAN050-E"

    /// Sitting dates encoded in each bundled fixture. Used by `selectedFixture()` to
    /// publish the active sitting date to evidence plans (so deep-link URLs can
    /// target `cabinetdoor://sitting/<date>` against the actually-seeded data).
    /// Keep this dictionary in sync with the XML files in
    /// `Resources/EvidenceFixtures/` and with `.evidence/regression-parliament-calendar.json`.
    static let fixtureDates: [String: String] = [
        "45-1-HAN020-E": "2025-06-20",
        "45-1-HAN050-E": "2025-11-04",
        "45-1-HAN100-E": "2026-03-26"
    ]

    /// Returns the selected fixture name and its sitting date string in `yyyy-MM-dd`,
    /// honoring the `EPAC_EVIDENCE_FIXTURE` env var when it names a bundled fixture.
    static func selectedFixture() -> (name: String, sittingDate: String) {
        let env = ProcessInfo.processInfo.environment["EPAC_EVIDENCE_FIXTURE"]
        if let env, let date = fixtureDates[env] {
            return (env, date)
        }
        // Default falls through if the env var is unset or names a fixture we don't
        // ship. We never crash the app over a misnamed evidence fixture — empty
        // state is a deterministic-enough fallback for the regression assertion.
        let fallbackDate = fixtureDates[defaultFixtureName] ?? ""
        return (defaultFixtureName, fallbackDate)
    }

    /// Loads the active fixture XML from the app bundle and persists it via the
    /// shared `Fetch.ingestHansard(xml:)` code path. No-op if not in evidence mode,
    /// if the bundle resource is missing, or if `ingestHansard` throws — the
    /// regression assertion still holds against empty state, and the QA-LLM step
    /// is expected to flag empty-state seed failures as follow-up issues rather
    /// than silent passes.
    static func seedIfNeeded(via fetch: Fetch) async {
        guard AppEnvironment.isEvidenceCaptureMode else { return }
        let fixture = selectedFixture()
        Log.debug("EvidenceFixtureSeed.seedIfNeeded(fixture: \(fixture.name))")
        guard let xml = loadFixtureXML(named: fixture.name) else {
            Log.error("EvidenceFixtureSeed: missing bundle resource for \(fixture.name)")
            return
        }
        do {
            try await fetch.ingestHansard(xml: xml)
        } catch {
            Log.error("EvidenceFixtureSeed: ingestHansard threw for \(fixture.name): \(error)")
        }
    }

    /// Reads a bundled fixture by resource name and returns its UTF-8 string contents.
    /// Returns `nil` if the resource is missing or unreadable — callers handle the
    /// nil case (no fatal). Made internal-but-explicit so unit tests can exercise
    /// the bundle-lookup behavior independently of the actor call.
    static func loadFixtureXML(named name: String) -> String? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "XML",
            subdirectory: "EvidenceFixtures"
        ) ?? Bundle.main.url(
            forResource: name,
            withExtension: "XML"
        ) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
