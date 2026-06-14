/// Reads the published versions of a bill from the backend.
///
/// `nil` means the backend has no versions record for the bill at all (404
/// or 204) — the bill page hides the "Compare versions" entry point. An
/// empty array means "bill is tracked but no version text has been ingested
/// yet" — same UI treatment as `nil`. A single-element array means only one
/// version has been ingested, and the diff viewer shows an empty state.
/// Throws only on transport or decoding failures.
protocol BillVersionsRepository: Sendable {
    func loadBillVersions(billID: String) async throws -> [BillVersion]?
}
