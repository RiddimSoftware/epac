//
//  SearchViewModel.swift
//  epac
//

import Foundation
import Observation

// Filters cached Hansard subjects by title across all fetched sittings.
// SearchResults are capped so SwiftUI doesn't choke on huge datasets.
@MainActor
@Observable
class SearchViewModel {
	var searchText = ""

	private static let maxSearchResults = 200

	// A result bundles the info needed to navigate: the hansard (for date +
	// navigation context) and the matched subject.
	struct SearchResult: Identifiable {
		let id: String  // subject hansardID
		let hansardDate: Date
		let parliamentNumber: Int
		let subject: SubjectOfBusiness
		let hansard: Hansard
	}

	func results(from hansards: [Hansard]) -> [SearchResult] {
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count >= 2 else { return [] }

		var found: [SearchResult] = []
		for hansard in hansards.sorted(by: { $0.date > $1.date }) {
			for order in hansard.orders {
				for subject in order.subjects where !subject.speeches.isEmpty {
					if subject.title.localizedCaseInsensitiveContains(trimmed) {
						found.append(SearchResult(
							id: subject.hansardID,
							hansardDate: hansard.date,
							parliamentNumber: hansard.parliamentNumber,
							subject: subject,
							hansard: hansard
						))
					}
					if found.count >= Self.maxSearchResults { return found }
				}
			}
		}
		return found
	}
}
