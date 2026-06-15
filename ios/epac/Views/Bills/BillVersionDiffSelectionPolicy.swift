import Foundation

/// Decides which bill-version pair the "Compare versions" viewer loads.
///
/// The viewer's natural default is "oldest published version → newest". But the
/// backend returns the *unavailable* state (HTTP 204/404, surfaced to iOS as a
/// `nil` diff) for a pair when one side has no comparable source text — so the
/// newest version is not always servable against the oldest. When that happens
/// the viewer would open on the "Couldn't load the diff…" state even though a
/// different pair has a real diff.
///
/// For the default selection this policy keeps `from` at the oldest version and
/// steps the `to` candidate from newest toward `from`, stopping at the first
/// pair the backend can actually serve, so the viewer opens on real content. If
/// no pair is servable it falls back to oldest → newest and lets the viewer
/// show its unavailable state.
///
/// A manual selection is loaded exactly as the user chose it — the policy never
/// steps away from a pair the user picked, even when that pair is unavailable.
///
/// This is a presentation-layer policy: it owns *which* pair to request, not how
/// the diff is computed. The clause-aware diff algorithm stays in the backend
/// behind the `LoadBillVersionDiff` use case, which the caller wraps in `probe`.
struct BillVersionDiffSelectionPolicy {
    /// What the viewer is trying to load.
    enum Intent: Equatable, Sendable {
        /// No manual selection yet — auto-select a servable pair.
        case auto
        /// The user picked this pair explicitly; load it as-is.
        case explicit(fromVersionID: String, toVersionID: String)
    }

    /// The resolved pair the viewer should display, plus the loaded diff. `diff`
    /// is `nil` when the chosen pair is unavailable (the viewer then shows its
    /// unavailable state with these pickers selected).
    struct Resolution: Equatable, Sendable {
        let fromVersionID: String
        let toVersionID: String
        let diff: BillVersionDiff?
    }

    /// Loads the diff for one candidate pair, returning `nil` when the backend
    /// cannot serve it (204/404, or a transport failure the caller chose to
    /// swallow). For `.auto` a `nil` means "this pair is unavailable, try the
    /// next candidate".
    typealias Probe = @Sendable (_ fromVersionID: String, _ toVersionID: String) async -> BillVersionDiff?

    /// Resolve the pair to display for the given intent.
    ///
    /// For `.auto`, makes at most `versions.count - 1` probe calls (one per
    /// candidate `to`), so request volume is bounded by the version count and
    /// never loops. For `.explicit`, makes exactly one probe call.
    func resolve(
        intent: Intent,
        versions: [BillVersion],
        probe: Probe
    ) async -> Resolution {
        switch intent {
        case .auto:
            return await resolveAuto(versions: versions, probe: probe)
        case let .explicit(fromVersionID, toVersionID):
            return await resolveExplicit(
                fromVersionID: fromVersionID,
                toVersionID: toVersionID,
                versions: versions,
                probe: probe
            )
        }
    }

    private func resolveAuto(
        versions: [BillVersion],
        probe: Probe
    ) async -> Resolution {
        let sorted = Self.sortedVersions(versions)
        guard let oldest = sorted.first else {
            return Resolution(fromVersionID: "", toVersionID: "", diff: nil)
        }
        let newest = sorted.last ?? oldest

        // Candidate `to` versions, newest first, down to (but not including)
        // `oldest`. The first pair the backend can serve wins — including a 200
        // with no clause-level changes, which is still an available state.
        for candidate in sorted.dropFirst().reversed() {
            if Task.isCancelled {
                return Resolution(fromVersionID: oldest.id, toVersionID: candidate.id, diff: nil)
            }
            if let diff = await probe(oldest.id, candidate.id) {
                return Resolution(fromVersionID: oldest.id, toVersionID: candidate.id, diff: diff)
            }
        }

        // No pair is servable: land on oldest → newest so the viewer shows its
        // canonical unavailable state with the default pair selected.
        return Resolution(fromVersionID: oldest.id, toVersionID: newest.id, diff: nil)
    }

    private func resolveExplicit(
        fromVersionID: String,
        toVersionID: String,
        versions: [BillVersion],
        probe: Probe
    ) async -> Resolution {
        var from = fromVersionID
        var to = toVersionID

        // Correct an out-of-order pick so `from` is the older version, matching
        // the viewer's before → after model. This mirrors the picker the user
        // sees once the selection settles.
        let sorted = Self.sortedVersions(versions)
        if let fromIndex = sorted.firstIndex(where: { $0.id == from }),
           let toIndex = sorted.firstIndex(where: { $0.id == to }),
           fromIndex > toIndex {
            swap(&from, &to)
        }

        let diff = await probe(from, to)
        return Resolution(fromVersionID: from, toVersionID: to, diff: diff)
    }

    /// Versions oldest → newest by `publishedOn`, falling back to label order
    /// when a publication date is missing. Matches how the viewer orders the
    /// pickers and what "oldest"/"newest" mean for the default pair.
    static func sortedVersions(_ versions: [BillVersion]) -> [BillVersion] {
        versions.sorted { lhs, rhs in
            switch (lhs.publishedOn, rhs.publishedOn) {
            case let (l?, r?):
                return l < r
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (nil, nil):
                return lhs.label < rhs.label
            }
        }
    }

    /// The viewer's initial pair before any diff loads: oldest → newest. Used to
    /// seed the pickers at init; the `.auto` resolve may then move `to` to an
    /// older, servable version.
    static func defaultPair(for versions: [BillVersion]) -> (fromVersionID: String, toVersionID: String) {
        let sorted = sortedVersions(versions)
        return (sorted.first?.id ?? "", sorted.last?.id ?? "")
    }
}
