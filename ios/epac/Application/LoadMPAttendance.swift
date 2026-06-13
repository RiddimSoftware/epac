//
//  LoadMPAttendance.swift
//  epac
//
//  Use case: compute an MP's attendance record and national / party comparison
//  from recorded-division tallies (EPAC-897). No new ingestion — this applies a
//  new lens to the vote data already gathered for the voting record (EPAC-23).
//
//  This is where the policy lives: a *paired* absence (a pre-arranged pairing,
//  common for travelling ministers) is reported separately from an unexplained
//  absence, so the two are never conflated.
//

import Foundation

struct LoadMPAttendance: Sendable {
	/// Minimum divisions an MP needs before they count toward a comparison
	/// average — keeps a single procedural vote from skewing the baseline.
	static let minimumDivisionsForComparison = 5

	private let port: any MPAttendanceQueryPort

	init(port: any MPAttendanceQueryPort) {
		self.port = port
	}

	/// Returns the member's attendance record plus an optional comparison, or
	/// `nil` when the member has no recorded divisions to summarise.
	@MainActor
	func execute(memberID: Int) async throws -> MPAttendance? {
		guard let tally = try await port.tally(forMemberID: memberID),
		      tally.totalDivisions > 0 else { return nil }

		let record = AttendanceRecord(
			totalDivisions: tally.totalDivisions,
			yea: tally.yea,
			nay: tally.nay,
			paired: tally.paired,
			denominatorStartDate: tally.denominatorStartDate
		)
		let comparison = try? await comparison(for: tally)
		return MPAttendance(record: record, comparison: comparison)
	}

	/// Builds national and same-party baselines from *other* MPs with enough
	/// recorded data. Each baseline is `nil` (and hidden by the UI) when too few
	/// peers are available, mirroring `PartyLineScoreView`'s graceful degradation.
	@MainActor
	private func comparison(for member: MemberDivisionTally) async throws -> AttendanceComparison? {
		let peers = try await port.allTallies().filter {
			$0.memberID != member.memberID &&
			$0.totalDivisions >= Self.minimumDivisionsForComparison
		}
		guard !peers.isEmpty else { return nil }

		let nationalRates = peers.map(Self.attendanceRate)
		let partyRates = peers.filter { $0.party == member.party }.map(Self.attendanceRate)

		let national = average(of: nationalRates)
		let party = average(of: partyRates)
		guard national != nil || party != nil else { return nil }

		return AttendanceComparison(
			party: member.party,
			nationalAverageRate: national,
			partyAverageRate: party,
			nationalSampleSize: nationalRates.count,
			partySampleSize: partyRates.count
		)
	}

	/// Present-rate (Yea + Nay over total divisions) for a single tally — the
	/// same definition used for the headline figure, so comparisons are apples
	/// to apples.
	static func attendanceRate(_ tally: MemberDivisionTally) -> Double {
		tally.totalDivisions > 0
			? Double(tally.yea + tally.nay) / Double(tally.totalDivisions)
			: 0
	}

	private func average(of rates: [Double]) -> Double? {
		guard !rates.isEmpty else { return nil }
		return rates.reduce(0, +) / Double(rates.count)
	}
}
