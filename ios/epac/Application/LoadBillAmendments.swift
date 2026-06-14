/// Loads the amendments tabled against one bill.
///
/// Returns `nil` when the backend has no amendments record for the bill, so
/// the caller can hide the "Amendments" panel without inspecting wire-format
/// details. An empty array means the bill is tracked but no amendments have
/// been tabled yet — the panel shows an empty-state row in that case (a UI
/// policy, per the feature's boundary rule).
struct LoadBillAmendments: Sendable {
    let repository: any BillAmendmentsRepository

    func execute(billID: String) async throws -> [BillAmendment]? {
        try await repository.loadBillAmendments(billID: billID)
    }
}
