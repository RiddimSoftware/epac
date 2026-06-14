/// Reads a clause-level diff between two published bill versions.
///
/// `nil` means the backend cannot produce a diff for the requested version
/// pair (either version is missing text, or the diff job has not run yet for
/// that pair) — the diff viewer renders an unavailable state. Throws only on
/// transport or decoding failures.
///
/// The clause-aware diff algorithm lives in the backend; iOS only renders the
/// structured result.
protocol BillVersionDiffRepository: Sendable {
    func loadBillVersionDiff(
        billID: String,
        fromVersionID: String,
        toVersionID: String
    ) async throws -> BillVersionDiff?
}
