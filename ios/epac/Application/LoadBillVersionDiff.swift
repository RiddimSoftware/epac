/// Loads the structured clause-level diff between two published bill versions.
///
/// Returns `nil` when the backend cannot produce a diff for the requested pair
/// — the diff viewer renders an unavailable state in that case. The clause-
/// aware diff algorithm lives in the backend; this use case is the application
/// policy boundary that the iOS view sits behind.
struct LoadBillVersionDiff: Sendable {
    let repository: any BillVersionDiffRepository

    func execute(
        billID: String,
        fromVersionID: String,
        toVersionID: String
    ) async throws -> BillVersionDiff? {
        try await repository.loadBillVersionDiff(
            billID: billID,
            fromVersionID: fromVersionID,
            toVersionID: toVersionID
        )
    }
}
