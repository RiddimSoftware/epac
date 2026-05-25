//
//  BrowseHansardSitting.swift
//  epac
//

import Foundation

struct HansardSittingSummary: Identifiable, Equatable, Sendable {
	let jurisdiction: Jurisdiction
	let sittingDate: Date
	let subjects: [SubjectOfBusinessRecord]

	var id: String { "\(jurisdiction.rawValue)-\(sittingDate.timeIntervalSince1970)" }
}

@MainActor
protocol BrowseHansardSittingUseCase: Sendable {
	func execute(
		jurisdiction: Jurisdiction,
		from startDate: Date,
		through endDate: Date
	) async throws -> BrowseHansardSitting.Result
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

	func execute(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> Result {
		guard startDate <= endDate else {
			return Result(sittingDates: [], sittings: [])
		}

		let sittingDates = try await repository.listSittingDates(
			jurisdiction: jurisdiction,
			from: startDate,
			through: endDate
		)
		.filter { startDate <= $0 && $0 <= endDate }
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
