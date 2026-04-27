//
//  SittingViewModel.swift
//  epac
//

import Observation

@Observable
@MainActor
class SittingViewModel {
	var searchText: String = ""

	/// Subjects in `order` that have speeches and match the current search query.
	/// Preserves the existing hansardID sort. When searchText is empty, all
	/// non-empty subjects are returned (unchanged behaviour from before search).
	func filteredSubjects(for order: OrderOfBusiness) -> [SubjectOfBusiness] {
		let sorted = order.subjects
			.filter { !$0.speeches.isEmpty }
			.sorted(by: { $0.hansardID < $1.hansardID })
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return sorted }
		return sorted.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
	}

	/// Returns orders paired with their filtered subjects in a single pass,
	/// eliminating the double call to filteredSubjects that visibleOrders + ForEach
	/// would otherwise cause.
	func visibleOrderSubjects(from hansard: Hansard) -> [(order: OrderOfBusiness, subjects: [SubjectOfBusiness])] {
		hansard.orders
			.filter { !$0.subjects.isEmpty }
			.sorted(by: { $0.hansardID < $1.hansardID })
			.compactMap { order -> (OrderOfBusiness, [SubjectOfBusiness])? in
				let subjects = filteredSubjects(for: order)
				return subjects.isEmpty ? nil : (order, subjects)
			}
	}
}
