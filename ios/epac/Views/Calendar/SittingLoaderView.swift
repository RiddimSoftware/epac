//
//  SittingLoaderView.swift
//  epac
//

import Sentry
import SwiftData
import SwiftUI

struct SittingLoaderView: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(\.hansardRepository) private var hansardRepository
	@EnvironmentObject private var fetch: Fetch

	let date: Date
	@Binding var selectedSubject: SubjectOfBusiness?

	@State private var loadState: LoadState = .loading

	var body: some View {
		Group {
			switch loadState {
			case .loading:
				ProgressView("Loading debates...")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			case .loaded(let hansard):
				SittingView(hansard: hansard, selectedSubject: $selectedSubject)
					.navigationDestination(item: $selectedSubject) { subject in
						SpeechView(hansard: hansard, subject: subject)
							.onDisappear { Log.debug("onDisappear") }
					}
			case .failed:
				ContentUnavailableView {
					Label("Couldn't load debates", systemImage: "exclamationmark.triangle")
				} description: {
					Text("Try again when you're back online.")
				} actions: {
					Button("Retry") {
						loadState = .loading
						Task { await loadHansard() }
					}
				}
			}
		}
		.navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
		.task(id: date) {
			await loadHansard()
		}
	}

	@MainActor
	private func loadHansard() async {
		selectedSubject = nil

		if let cached = fetchHansard() {
			loadState = .loaded(cached)
			return
		}

		do {
			_ = try await LoadDailyHansard(repository: hansardRepository).execute(
				jurisdiction: .federal,
				sittingDate: date
			)
			guard let hansard = fetchHansard() else {
				loadState = .failed
				return
			}
			loadState = .loaded(hansard)
			updateRecentSubjects(for: hansard)
		} catch {
			Log.debug("Failed to fetch hansard \(date): \(error.localizedDescription)")
			SentrySDK.capture(error: error)
			loadState = .failed
		}
	}

	private func fetchHansard() -> Hansard? {
		try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first
	}

	private func updateRecentSubjects(for hansard: Hansard) {
		let subjects = hansard.orders.flatMap { $0.subjects }
		let titles = subjects.map { $0.title }
		WidgetDataWriter.writeRecentSubjects(titles)
		WidgetDataWriter.reloadWidgets()
	}
}

private enum LoadState {
	case loading
	case loaded(Hansard)
	case failed
}
