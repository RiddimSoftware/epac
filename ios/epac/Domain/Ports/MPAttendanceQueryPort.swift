//
//  MPAttendanceQueryPort.swift
//  epac
//
//  Port for reading recorded-division counts out of the votes data store.
//  Implementations surface raw tallies only — the policy decision that a
//  paired absence is treated differently from an unexplained one is applied
//  by `LoadMPAttendance`, never by the adapter (EPAC-897 boundary rule).
//

@MainActor
protocol MPAttendanceQueryPort: Sendable {
	/// Tally for a single member, or `nil` when there are no recorded divisions
	/// for that member while they were sitting.
	func tally(forMemberID memberID: Int) async throws -> MemberDivisionTally?

	/// Tallies for every member with recorded vote data, used to build the
	/// national and party comparison baselines.
	func allTallies() async throws -> [MemberDivisionTally]
}
