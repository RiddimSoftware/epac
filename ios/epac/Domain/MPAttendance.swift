//
//  MPAttendance.swift
//  epac
//
//  Attendance value objects for an MP's recorded-division record (EPAC-897).
//  These are computed from already-ingested vote data (`MemberVote.type`):
//  every recorded division marks each MP as Yea, Nay, Paired, or Absent.
//
//  Domain layer: no persistence and no presentation concepts. The
//  "a paired absence is not an unexplained absence" rule lives in the
//  `LoadMPAttendance` use case, not here and not in the data adapter.
//

import Foundation

/// Raw per-member division counts surfaced by the data adapter. The adapter
/// reports counts only; deriving the absence count, the attendance rate, and
/// any comparison is the use case's job (EPAC-897 boundary rule).
struct MemberDivisionTally: Sendable, Equatable {
	let memberID: Int
	let party: Party
	/// Divisions where the member voted Yea.
	let yea: Int
	/// Divisions where the member voted Nay.
	let nay: Int
	/// Divisions where the member was Paired (a pre-arranged, cancelled-out absence).
	let paired: Int
	/// Total recorded divisions held while this member was a sitting member —
	/// the denominator. Divisions before the member was sworn in are excluded.
	let totalDivisions: Int
	/// The date the member was sworn in, when known; powers the "since <date>" label.
	let denominatorStartDate: Date?
}

/// A computed attendance record for one MP — how often they showed up to vote.
///
/// `absent` is *derived* (`total − yea − nay − paired`) rather than counted, so
/// the figure is correct whether or not the source feed emits explicit "Absent"
/// rows for divisions a member skipped.
struct AttendanceRecord: Sendable, Equatable {
	let totalDivisions: Int
	let yea: Int
	let nay: Int
	let paired: Int
	let denominatorStartDate: Date?

	/// Divisions where the member cast a recorded Yea or Nay — i.e. was present.
	var present: Int { yea + nay }

	/// Divisions missed *without* a pairing arrangement (unexplained absences).
	/// Kept distinct from `paired` so ministers' pre-arranged absences are not
	/// lumped in with simply not showing up.
	var absent: Int { max(0, totalDivisions - yea - nay - paired) }

	/// Fraction of divisions the member was present for, in `0...1`.
	var attendanceRate: Double {
		totalDivisions > 0 ? Double(present) / Double(totalDivisions) : 0
	}
}

/// National and same-party attendance baselines an MP can be compared against.
/// Each average is computed across *other* MPs for whom recorded vote data is
/// available locally; a `nil` average means there was not enough data to show one.
struct AttendanceComparison: Sendable, Equatable {
	let party: Party
	/// Mean attendance rate across other MPs with recorded data (`0...1`), or `nil`.
	let nationalAverageRate: Double?
	/// Mean attendance rate across other same-party MPs (`0...1`), or `nil`.
	let partyAverageRate: Double?
	/// Number of other MPs in the national sample (shown so the figure is honest).
	let nationalSampleSize: Int
	/// Number of other same-party MPs in the party sample.
	let partySampleSize: Int
}

/// Combined result returned by `LoadMPAttendance`: the MP's own record plus an
/// optional comparison against national and party baselines.
struct MPAttendance: Sendable, Equatable {
	let record: AttendanceRecord
	let comparison: AttendanceComparison?
}
