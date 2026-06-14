/// Loads the amendments tabled against one bill.
///
/// Surfaces the amendment number, mover, stage, status, and short clause
/// reference for each amendment, with verbatim amendment text available on
/// tap. Returns an empty array when no amendments have been tabled — the
/// "Amendments" panel renders that case as an empty-state row rather than
/// hiding (so users see the feature exists even before any amendments).
struct LoadBillAmendments: Sendable {
    let repository: any BillAmendmentsRepository

    func execute(billID: String) async throws -> [BillAmendment] {
        try await repository.loadBillAmendments(billID: billID)
    }
}
