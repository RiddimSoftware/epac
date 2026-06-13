//
//  SwiftDataMPAttendanceAdapter.swift
//  epac
//
//  Adapter for `MPAttendanceQueryPort` backed by the local SwiftData store
//  (EPAC-897). The division universe is the set of federal `RecordedVote`s
//  already synced for the voting record; a member's ballots come from their
//  `MemberVote` rows. Divisions before a member's sworn-in date are never
//  counted, so new and by-election MPs are judged only on their own term.
//
//  This adapter surfaces raw counts (Yea / Nay / Paired + total divisions) and
//  applies no presentation policy — that is `LoadMPAttendance`'s job.
//

import Foundation
import SwiftData

@MainActor
struct SwiftDataMPAttendanceAdapter: MPAttendanceQueryPort {
	private let modelContext: ModelContext

	init(modelContext: ModelContext) {
		self.modelContext = modelContext
	}

	func tally(forMemberID memberID: Int) async throws -> MemberDivisionTally? {
		let divisionDates = try federalDivisionDates()
		guard !divisionDates.isEmpty,
		      let member = try member(withID: memberID) else { return nil }
		let votes = try modelContext.fetch(FetchDescriptor<MemberVote>(
			predicate: #Predicate { $0.memberID == memberID }
		))
		return tally(for: member, votes: votes, divisionDates: divisionDates)
	}

	func allTallies() async throws -> [MemberDivisionTally] {
		let divisionDates = try federalDivisionDates()
		guard !divisionDates.isEmpty else { return [] }

		let members = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
			.filter { $0.memberID > 0 && $0.jurisdiction == .federal }
		let votesByMember = Dictionary(
			grouping: try modelContext.fetch(FetchDescriptor<MemberVote>()),
			by: \.memberID
		)

		// Counting eligible divisions is keyed only on the sworn-in date, so
		// memoise it — most sitting members share the same (or no) start date.
		var eligibleCountCache: [Date?: Int] = [:]
		return members.compactMap { member in
			guard let votes = votesByMember[member.memberID], !votes.isEmpty else { return nil }
			return tally(
				for: member,
				votes: votes,
				divisionDates: divisionDates,
				eligibleCountCache: &eligibleCountCache
			)
		}
	}

	// MARK: - Tally

	private func tally(
		for member: ParliamentMember,
		votes: [MemberVote],
		divisionDates: [Int: Date],
		eligibleCountCache: inout [Date?: Int]
	) -> MemberDivisionTally {
		let start = member.fromDateTime
		let eligibleCount: Int
		if let cached = eligibleCountCache[start] {
			eligibleCount = cached
		} else {
			eligibleCount = countEligibleDivisions(divisionDates, since: start)
			eligibleCountCache[start] = eligibleCount
		}
		return buildTally(member: member, votes: votes, divisionDates: divisionDates, start: start, eligibleCount: eligibleCount)
	}

	private func tally(
		for member: ParliamentMember,
		votes: [MemberVote],
		divisionDates: [Int: Date]
	) -> MemberDivisionTally {
		let start = member.fromDateTime
		let eligibleCount = countEligibleDivisions(divisionDates, since: start)
		return buildTally(member: member, votes: votes, divisionDates: divisionDates, start: start, eligibleCount: eligibleCount)
	}

	private func buildTally(
		member: ParliamentMember,
		votes: [MemberVote],
		divisionDates: [Int: Date],
		start: Date?,
		eligibleCount: Int
	) -> MemberDivisionTally {
		var yea = 0, nay = 0, paired = 0
		for vote in votes {
			// Only count ballots on divisions in the eligible window. A ballot
			// whose division isn't in the local store (e.g. a prior parliament)
			// is skipped so it can't outweigh the denominator.
			guard let date = divisionDates[vote.voteID], isEligible(date, since: start) else { continue }
			switch vote.recordedVote.lowercased() {
			case "yea": yea += 1
			case "nay": nay += 1
			case "paired": paired += 1
			default: break  // "Absent" / other — folded into derived absences
			}
		}
		// The denominator is the eligible-division count, but never fewer than
		// this member's own recorded participations (a safety floor).
		let total = max(eligibleCount, yea + nay + paired)
		return MemberDivisionTally(
			memberID: member.memberID,
			party: member.party,
			yea: yea,
			nay: nay,
			paired: paired,
			totalDivisions: total,
			denominatorStartDate: start
		)
	}

	// MARK: - Division universe

	/// Maps each federal division's `voteID` to its date.
	private func federalDivisionDates() throws -> [Int: Date] {
		let federal = Jurisdiction.federal.rawValue
		let divisions = try modelContext.fetch(FetchDescriptor<RecordedVote>(
			predicate: #Predicate { $0.jurisdiction == federal }
		))
		return Dictionary(divisions.map { ($0.voteID, $0.date) }, uniquingKeysWith: { first, _ in first })
	}

	private func countEligibleDivisions(_ divisionDates: [Int: Date], since start: Date?) -> Int {
		guard let start else { return divisionDates.count }
		return divisionDates.values.reduce(into: 0) { count, date in
			if date >= start { count += 1 }
		}
	}

	private func isEligible(_ date: Date, since start: Date?) -> Bool {
		guard let start else { return true }
		return date >= start
	}

	private func member(withID memberID: Int) throws -> ParliamentMember? {
		try modelContext.fetch(FetchDescriptor<ParliamentMember>(
			predicate: #Predicate { $0.memberID == memberID }
		)).first
	}
}
