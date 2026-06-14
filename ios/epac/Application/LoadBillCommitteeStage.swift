/// Loads the committee study stage for one bill.
///
/// Surfaces the committee currently studying the bill, with study dates,
/// upcoming meetings, and past meetings with witness counts. Returns `nil` when
/// the bill is not before a committee; the "In committee" panel hides itself in
/// that case (a UI-layer policy, per the feature's boundary rule).
struct LoadBillCommitteeStage: Sendable {
    let repository: any BillCommitteeStageRepository

    func execute(billID: String) async throws -> BillCommitteeStage? {
        try await repository.loadBillCommitteeStage(billID: billID)
    }
}
