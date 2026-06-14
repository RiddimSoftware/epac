/// Reads the amendments tabled against a bill.
///
/// Returns an empty array when the bill has no amendments yet — the panel
/// renders an explicit empty state in that case rather than hiding. Throws
/// only on transport or decoding failures.
protocol BillAmendmentsRepository: Sendable {
    func loadBillAmendments(billID: String) async throws -> [BillAmendment]
}
