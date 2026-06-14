/// Reads a bill's committee study stage.
///
/// Returns `nil` when the bill is not (and has not been) before a committee, so
/// the caller can hide the "In committee" panel without inspecting wire-format
/// details. Throws only on transport or decoding failures.
protocol BillCommitteeStageRepository: Sendable {
    func loadBillCommitteeStage(billID: String) async throws -> BillCommitteeStage?
}
