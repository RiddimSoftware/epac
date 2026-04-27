//
//  SittingViewModel.swift
//  epac
//

import Observation

@Observable
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
}
