//
//  BrowseHansardSitting.swift
//  epac
//

import Foundation

struct HansardSittingSummary: Identifiable, Equatable, Sendable {
	let jurisdiction: Jurisdiction
	let sittingDate: Date
	let subjects: [SubjectOfBusinessRecord]

	var id: String { "\(jurisdiction.id)-\(sittingDate.timeIntervalSince1970)" }
}

@MainActor
protocol BrowseHansardSittingUseCase: Sendable {
	func execute(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> BrowseHansardSitting.Result
}

@MainActor
struct BrowseHansardSitting: BrowseHansardSittingUseCase {
	struct Result: Equatable, Sendable {
		let sittingDates: [Date]
		let sittings: [HansardSittingSummary]
	}

	private let repository: any HansardRepository

	init(repository: any HansardRepository) {
		self.repository = repository
	}

	func execute(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> Result {
		guard from <= to else {
			return Result(sittingDates: [], sittings: [])
		}

		let sittingDates = try await repository.listSittingDates(
			jurisdiction: jurisdiction,
			from: from,
			to: to
		)
		.filter { from <= $0 && $0 <= to }
		.removingDuplicates()
		.sorted()

		var summaries: [HansardSittingSummary] = []
		for sittingDate in sittingDates {
			let subjects = (try? await repository.fetchTranscript(
				jurisdiction: jurisdiction,
				sittingDate: sittingDate
			).subjects) ?? []
			summaries.append(HansardSittingSummary(
				jurisdiction: jurisdiction,
				sittingDate: sittingDate,
				subjects: subjects
			))
		}

		return Result(sittingDates: sittingDates, sittings: summaries)
	}
}

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
