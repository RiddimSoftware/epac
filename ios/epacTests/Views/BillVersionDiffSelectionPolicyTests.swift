@testable import epac
import Foundation
import Testing

/// Covers the default-pair selection behaviour for the bill diff viewer
/// (EPAC-2309): auto-stepping to a servable pair, the all-unavailable fallback,
/// bounded request volume, the single-version no-request case, and respect for a
/// manual selection.
struct BillVersionDiffSelectionPolicyTests {
    // MARK: - Auto selection

    /// C-11 shape: oldest → middle → newest, where oldest→newest is unavailable
    /// (the live 204) but oldest→middle is a populated 200. The policy must step
    /// `to` from the newest down and land on the servable middle pair.
    @Test func autoSelectsFirstServablePairSteppingFromNewest() async {
        let recorder = ProbeRecorder(servable: [
            key(Self.firstReading, Self.asAmended): Self.populatedDiff
        ])
        let policy = BillVersionDiffSelectionPolicy()

        // Pass scrambled order to prove the policy sorts oldest → newest itself.
        let resolution = await policy.resolve(
            intent: .auto,
            versions: [Self.asPassed, Self.firstReading, Self.asAmended],
            probe: recorder.probe
        )

        #expect(resolution.fromVersionID == Self.firstReading.id)
        #expect(resolution.toVersionID == Self.asAmended.id)
        #expect(resolution.diff?.clauseDiffs.isEmpty == false)
        // Newest first (204 → skip), then the next-older candidate (200 → stop).
        #expect(recorder.calls == [
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asPassed.id),
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asAmended.id)
        ])
    }

    /// A 200 with no clause-level changes is still an available state, so the
    /// policy stops at the newest pair and does not keep stepping looking for a
    /// populated diff.
    @Test func autoStopsAtFirstServablePairEvenWhenNewestHasNoChanges() async {
        let recorder = ProbeRecorder(servable: [
            key(Self.firstReading, Self.asPassed): Self.noChangesDiff
        ])
        let policy = BillVersionDiffSelectionPolicy()

        let resolution = await policy.resolve(
            intent: .auto,
            versions: [Self.firstReading, Self.asAmended, Self.asPassed],
            probe: recorder.probe
        )

        #expect(resolution.fromVersionID == Self.firstReading.id)
        #expect(resolution.toVersionID == Self.asPassed.id)
        #expect(resolution.diff?.clauseDiffs.isEmpty == true)
        #expect(recorder.calls == [
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asPassed.id)
        ])
    }

    /// When no pair is servable, the policy falls back to oldest → newest with no
    /// diff so the viewer shows its canonical unavailable state.
    @Test func autoFallsBackToOldestNewestWhenNoPairIsServable() async {
        let recorder = ProbeRecorder(servable: [:])
        let policy = BillVersionDiffSelectionPolicy()

        let resolution = await policy.resolve(
            intent: .auto,
            versions: [Self.firstReading, Self.asAmended, Self.asPassed],
            probe: recorder.probe
        )

        #expect(resolution.fromVersionID == Self.firstReading.id)
        #expect(resolution.toVersionID == Self.asPassed.id)
        #expect(resolution.diff == nil)
        // Every candidate `to` is tried exactly once, newest → oldest+1.
        #expect(recorder.calls == [
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asPassed.id),
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asAmended.id)
        ])
    }

    /// Request volume is bounded by the version count: at most `count - 1` probe
    /// calls (one per candidate `to`), and the endpoint is never re-hit in a
    /// loop.
    @Test func autoMakesBoundedNumberOfRequests() async {
        let versions = [Self.firstReading, Self.asAmended, Self.asPassed, Self.royalAssent]
        let recorder = ProbeRecorder(servable: [:])
        let policy = BillVersionDiffSelectionPolicy()

        _ = await policy.resolve(intent: .auto, versions: versions, probe: recorder.probe)

        #expect(recorder.calls.count == versions.count - 1)
        #expect(recorder.calls.count <= versions.count)
    }

    /// A single-version bill is never diffable, so the policy must not probe the
    /// endpoint at all (the viewer shows its "only one version" empty state).
    @Test func autoMakesNoRequestForSingleVersion() async {
        let recorder = ProbeRecorder(servable: [:])
        let policy = BillVersionDiffSelectionPolicy()

        let resolution = await policy.resolve(
            intent: .auto,
            versions: [Self.firstReading],
            probe: recorder.probe
        )

        #expect(recorder.calls.isEmpty)
        #expect(resolution.diff == nil)
    }

    // MARK: - Manual selection

    /// A manual pick is loaded exactly as chosen and is respected even when it is
    /// the unavailable pair — the policy must not step away to find a servable
    /// pair, which would override the user's choice.
    @Test func explicitSelectionIsRespectedAndNotSteppedAwayFrom() async {
        // The middle pair is servable, but the user explicitly picked the
        // unavailable newest pair.
        let recorder = ProbeRecorder(servable: [
            key(Self.firstReading, Self.asAmended): Self.populatedDiff
        ])
        let policy = BillVersionDiffSelectionPolicy()

        let resolution = await policy.resolve(
            intent: .explicit(fromVersionID: Self.firstReading.id, toVersionID: Self.asPassed.id),
            versions: [Self.firstReading, Self.asAmended, Self.asPassed],
            probe: recorder.probe
        )

        #expect(resolution.fromVersionID == Self.firstReading.id)
        #expect(resolution.toVersionID == Self.asPassed.id)
        #expect(resolution.diff == nil)
        // Exactly the chosen pair, with no stepping to the servable middle pair.
        #expect(recorder.calls == [
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asPassed.id)
        ])
    }

    /// A servable manual pick returns its diff with a single probe call.
    @Test func explicitSelectionLoadsChosenServablePair() async {
        let recorder = ProbeRecorder(servable: [
            key(Self.firstReading, Self.asAmended): Self.populatedDiff
        ])
        let policy = BillVersionDiffSelectionPolicy()

        let resolution = await policy.resolve(
            intent: .explicit(fromVersionID: Self.firstReading.id, toVersionID: Self.asAmended.id),
            versions: [Self.firstReading, Self.asAmended, Self.asPassed],
            probe: recorder.probe
        )

        #expect(resolution.fromVersionID == Self.firstReading.id)
        #expect(resolution.toVersionID == Self.asAmended.id)
        #expect(resolution.diff?.clauseDiffs.isEmpty == false)
        #expect(recorder.calls.count == 1)
    }

    /// An out-of-order manual pick (newer `from`, older `to`) is corrected so
    /// `from` is the older version, matching the viewer's before → after model.
    @Test func explicitSelectionCorrectsOutOfOrderPair() async {
        let recorder = ProbeRecorder(servable: [:])
        let policy = BillVersionDiffSelectionPolicy()

        let resolution = await policy.resolve(
            intent: .explicit(fromVersionID: Self.asPassed.id, toVersionID: Self.firstReading.id),
            versions: [Self.firstReading, Self.asAmended, Self.asPassed],
            probe: recorder.probe
        )

        #expect(resolution.fromVersionID == Self.firstReading.id)
        #expect(resolution.toVersionID == Self.asPassed.id)
        #expect(recorder.calls == [
            ProbeRecorder.Pair(from: Self.firstReading.id, to: Self.asPassed.id)
        ])
    }

    // MARK: - Fixtures

    private static let firstReading = makeVersion(
        id: "c-11-first-reading",
        label: "First reading",
        stage: "First Reading",
        publishedOn: "2026-02-01"
    )
    private static let asAmended = makeVersion(
        id: "c-11-as-amended-by-committee",
        label: "As amended by committee",
        stage: "Report Stage",
        publishedOn: "2026-03-01"
    )
    private static let asPassed = makeVersion(
        id: "c-11-as-passed-by-house",
        label: "As passed by the House of Commons",
        stage: "Third Reading",
        publishedOn: "2026-04-01"
    )
    private static let royalAssent = makeVersion(
        id: "c-11-royal-assent",
        label: "Royal Assent",
        stage: "Royal Assent",
        publishedOn: "2026-05-01"
    )

    private static let populatedDiff = BillVersionDiff(
        fromVersion: firstReading,
        toVersion: asAmended,
        clauseDiffs: [
            BillClauseDiff(
                id: "clause-3",
                label: "Clause 3",
                changeType: .modified,
                fromText: "The Minister shall report annually.",
                toText: "The Minister shall report quarterly.",
                hansardAnchorURL: nil
            )
        ]
    )

    private static let noChangesDiff = BillVersionDiff(
        fromVersion: firstReading,
        toVersion: asPassed,
        clauseDiffs: []
    )

    private static func makeVersion(
        id: String,
        label: String,
        stage: String,
        publishedOn: String
    ) -> BillVersion {
        BillVersion(
            id: id,
            label: label,
            title: nil,
            stage: stage,
            chamber: "House of Commons",
            publishedOn: date(publishedOn),
            sourceURL: nil
        )
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}

private func key(_ from: BillVersion, _ to: BillVersion) -> String {
    "\(from.id)::\(to.id)"
}

/// Records the pairs the policy probes and returns a preconfigured diff for the
/// servable pairs (any other pair is "unavailable" → `nil`). The policy awaits
/// probes one at a time, so the unsynchronised call log is safe here.
private final class ProbeRecorder: @unchecked Sendable {
    struct Pair: Equatable, Sendable {
        let from: String
        let to: String
    }

    private(set) var calls: [Pair] = []
    private let servable: [String: BillVersionDiff]

    init(servable: [String: BillVersionDiff]) {
        self.servable = servable
    }

    var probe: BillVersionDiffSelectionPolicy.Probe {
        { [self] from, to in
            calls.append(Pair(from: from, to: to))
            return servable["\(from)::\(to)"]
        }
    }
}
