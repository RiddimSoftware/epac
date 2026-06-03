//
//  BrowseHansardSitting.swift
//  epac
//

import Foundation

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
	}

	private let repository: any SittingRepository

	init(repository: any SittingRepository) {
		self.repository = repository
	}

	func execute(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> Result {
		guard startDate <= endDate else {
			return Result(sittingDates: [])
		}

		let sittingDates = try await repository.listSittingDates(
			jurisdiction: jurisdiction,
			from: startDate,
			through: endDate
		)
		.filter { startDate <= $0 && $0 <= endDate }
		.removingDuplicates()
		.sorted()

		return Result(sittingDates: sittingDates)
	}
}

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
