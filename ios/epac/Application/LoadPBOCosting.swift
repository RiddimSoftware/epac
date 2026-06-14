import Foundation

/// Loads the independent PBO costing for one bill.
///
/// The use case sorts all linked notes by publication date and returns the
/// latest note as the primary panel content. Older notes are preserved as links
/// in the reader. Returning `nil` tells the UI to render no panel at all.
struct LoadPBOCosting: Sendable {
    let queryPort: any PBOCostingQueryPort

    func execute(billID: String) async throws -> PBOCostingResult? {
        guard let costings = try await queryPort.loadPBOCostings(billID: billID),
              !costings.isEmpty else {
            return nil
        }

        let sortedCostings = costings.sorted { lhs, rhs in
            let lhsDate = lhs.publishedAt ?? .distantPast
            let rhsDate = rhs.publishedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.id < rhs.id
        }

        guard let latest = sortedCostings.first else { return nil }
        return PBOCostingResult(latest: latest, otherReports: Array(sortedCostings.dropFirst()))
    }
}
