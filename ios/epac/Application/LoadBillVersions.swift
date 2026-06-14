/// Loads the published versions of one bill.
///
/// Returns `nil` when the backend has no versions record for the bill — the
/// caller hides the "Compare versions" entry point in that case. An empty
/// array gets the same UI treatment. A single-element array means only one
/// version has been ingested and the diff viewer's empty state applies.
struct LoadBillVersions: Sendable {
    let repository: any BillVersionsRepository

    func execute(billID: String) async throws -> [BillVersion]? {
        try await repository.loadBillVersions(billID: billID)
    }
}
