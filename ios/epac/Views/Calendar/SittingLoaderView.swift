//
//  SittingLoaderView.swift
//  epac
//

import Sentry
import SwiftData
import SwiftUI

private enum SittingLoaderLayout {
	static let bannerSpacing = EpacSpacing.s
	static let bannerVerticalPadding: CGFloat = 10
}

struct SittingLoaderView: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(\.hansardRepository) private var hansardRepository
	@Environment(NetworkMonitor.self) private var networkMonitor
	@EnvironmentObject private var fetch: Fetch

	let date: Date
	@Binding var selectedSubject: SubjectOfBusiness?
	var initialInterventionID: String?

	@State private var loadState: LoadState = .loading
	@State private var offlineLoadMessage: String?

	var body: some View {
		Group {
			switch loadState {
			case .loading:
				ProgressView("Loading debates...")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			case .loaded(let hansard):
				SittingView(
					hansard: hansard,
					selectedSubject: $selectedSubject,
					initialInterventionID: initialInterventionID
				)
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
		.safeAreaInset(edge: .bottom) {
			if let offlineLoadMessage {
				HStack(spacing: SittingLoaderLayout.bannerSpacing) {
					Image(systemName: "wifi.slash")
					Text(offlineLoadMessage)
						.font(.footnote)
					Spacer()
				}
				.foregroundStyle(.white)
				.padding(.horizontal)
				.padding(.vertical, SittingLoaderLayout.bannerVerticalPadding)
				.background(Color.appWarning)
			}
		}
	}

	@MainActor
	private func loadHansard() async {
		selectedSubject = nil
		offlineLoadMessage = nil

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
				updateOfflineLoadMessage()
				loadState = .failed
				return
			}
			loadState = .loaded(hansard)
			updateRecentSubjects(for: hansard)
		} catch {
			Log.debug("Failed to fetch hansard \(date): \(error.localizedDescription)")
			SentrySDK.capture(error: error)
			updateOfflineLoadMessage()
			loadState = .failed
		}
	}

	@MainActor
	private func updateOfflineLoadMessage() {
		guard initialInterventionID != nil,
		      !networkMonitor.isConnected else {
			offlineLoadMessage = nil
			return
		}
		offlineLoadMessage = "Couldn't load that debate offline. Connect to the network and try again."
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
