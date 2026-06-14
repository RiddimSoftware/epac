/// Loads PBO costing notes linked to a bill by the backend.
///
/// `nil` means the backend has no PBO link record for the bill, so the bill
/// page hides the costing panel. An empty array is also valid and means the
/// bill has a record but no renderable notes.
protocol PBOCostingQueryPort: Sendable {
    func loadPBOCostings(billID: String) async throws -> [PBOCosting]?
}
