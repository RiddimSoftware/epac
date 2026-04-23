//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftUI
import SwiftData
import Foundation
import Observation

struct ContentView: View {
	@Environment(\.modelContext) var modelContext
	var fetch: Fetch
	@State private var viewModel = ContentViewModel()
	@State private var router = NavigationRouter()
	@Query private var members: [ParliamentMember]
	@Query private var constituencies: [Constituency]

	init(modelContainer: ModelContainer) {
		self.fetch = Fetch(modelContainer: modelContainer)
	}

	var body: some View {
		TabView(selection: $router.selectedTab) {
			NavigationStack {
				SittingCalendarView(selectedDate: $viewModel.selectedDate)
					.environmentObject(fetch)
					.navigationDestination(item: $viewModel.selectedHansard) { hansard in
						SittingView(hansard: hansard, selectedSubject: $viewModel.selectedSubject)
							.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
							.navigationDestination(item: $viewModel.selectedSubject, destination: { subject in
								SpeechView(hansard: hansard, subject: subject)
									.onDisappear {
										Log.debug("onDisappear")
									}
							})
					}
					.navigationDestination(item: $viewModel.nonSittingDate) { date in
						NonSittingDayView(date: date)
					}
					.onChange(of: viewModel.selectedDate) { _, newValue in
						viewModel.onSelectedDateChanged(to: newValue, modelContext: modelContext, fetch: fetch)
					}
			}
			.tabItem {
				Label(AppTab.sittingCalendar.title, systemImage: AppTab.sittingCalendar.systemImageName)
			}
			.tag(AppTab.sittingCalendar)

			ExpendituresView()
				.tabItem {
					Label(AppTab.expenditures.title, systemImage: AppTab.expenditures.systemImageName)
				}
				.tag(AppTab.expenditures)
		}
		.environmentObject(fetch)
		.environment(router)
		.onOpenURL { url in
			viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
		}
		.task {
			await viewModel.downloadInitialData(members: members, constituencies: constituencies, fetch: fetch)
		}
	}
}


