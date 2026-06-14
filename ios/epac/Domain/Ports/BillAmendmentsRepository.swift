/// Reads amendments tabled against a bill.
///
/// `nil` means the backend has no amendments record for the bill at all (404
/// or 204) — the panel hides itself. An empty array means "bill is tracked but
/// no amendments tabled yet" — the panel shows an empty-state row. Throws only
/// on transport or decoding failures.
protocol BillAmendmentsRepository: Sendable {
    func loadBillAmendments(billID: String) async throws -> [BillAmendment]?
}
