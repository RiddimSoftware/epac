//
//  SearchView.swift
//  epac
//

import SwiftUI
import SwiftData

struct SearchView: View {
	@EnvironmentObject var fetch: Fetch
	@Environment(\.modelContext) var modelContext
	@Environment(NavigationRouter.self) var router

	@Query(sort: [SortDescriptor(\Hansard.date, order: .reverse)])
	private var hansards: [Hansard]

	@State private var viewModel = SearchViewModel()
	@State private var selectedHansard: Hansard?
	@State private var selectedSubject: SubjectOfBusiness?

	private var results: [SearchViewModel.SearchResult] {
		viewModel.results(from: hansards)
	}

	var body: some View {
		NavigationStack {
			Group {
				if viewModel.isQueryTooShort {
					promptView
				} else if results.isEmpty {
					ContentUnavailableView.search(text: viewModel.searchText)
				} else {
					resultsList
				}
			}
			.navigationTitle("Search")
			.searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search debates")
			.navigationDestination(item: $selectedHansard) { hansard in
				SittingView(hansard: hansard, selectedSubject: $selectedSubject)
					.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
					.navigationDestination(item: $selectedSubject) { subject in
						SpeechView(hansard: hansard, subject: subject)
					}
			}
		}
		.environmentObject(fetch)
	}

	private var promptView: some View {
		VStack(spacing: 12) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 48))
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			Text("Search debate topics")
				.font(.headline)
			Text("Searches across all sitting days you've opened.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var resultsList: some View {
		List(results) { result in
			Button {
				selectedSubject = result.subject
				selectedHansard = result.hansard
			} label: {
				VStack(alignment: .leading, spacing: 4) {
					Text(result.subject.title)
						.font(.headline)
						.foregroundStyle(.primary)
					Text(result.hansardDate.formatted(date: .long, time: .omitted))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, 2)
			}
			.accessibilityLabel(result.subject.title)
			.accessibilityHint(result.hansardDate.formatted(date: .long, time: .omitted))
		}
		.listStyle(.plain)
	}
}
