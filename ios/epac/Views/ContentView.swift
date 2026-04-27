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
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	var fetch: Fetch
	@Environment(NotificationManager.self) private var notificationManager
	@State private var viewModel = ContentViewModel()
	@State private var router = NavigationRouter()
	@State private var networkMonitor = NetworkMonitor()
	@Query private var members: [ParliamentMember]
	@Query private var constituencies: [Constituency]

	init(modelContainer: ModelContainer) {
		self.fetch = Fetch(modelContainer: modelContainer)
	}

	var body: some View {
		Group {
			if horizontalSizeClass == .compact {
				phoneLayout
			} else {
				iPadLayout
			}
		}
		.environmentObject(fetch)
		.environment(router)
		.onOpenURL { url in
			viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
		}
		.onChange(of: notificationManager.pendingDate) { _, date in
			guard let date else { return }
			let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
			viewModel.selectedDate = components
			viewModel.onSelectedDateChanged(to: components, modelContext: modelContext, fetch: fetch)
			router.selectedTab = .sittingCalendar
			notificationManager.clearPendingDate()
		}
		.task {
			networkMonitor.start()
			await viewModel.downloadInitialData(members: members, constituencies: constituencies, fetch: fetch)
			// Request notification permission after initial content is loaded,
			// so the system prompt appears in context rather than at cold launch.
			await notificationManager.requestAuthorization()
		}
	}

	// MARK: - Offline banner

	@ViewBuilder
	private var offlineBanner: some View {
		if !networkMonitor.isConnected {
			HStack(spacing: 10) {
				Image(systemName: "wifi.slash")
				Text("You're offline. Showing cached content.")
					.font(.footnote)
				Spacer()
			}
			.foregroundStyle(.white)
			.padding(.horizontal)
			.padding(.vertical, 10)
			.background(Color(UIColor.systemOrange))
		}
	}

	// MARK: - Phone layout (compact size class)

	private var phoneLayout: some View {
		TabView(selection: $router.selectedTab) {
			calendarStack
				.tabItem { Label(AppTab.sittingCalendar.title, systemImage: AppTab.sittingCalendar.systemImageName) }
				.tag(AppTab.sittingCalendar)

			SearchView()
				.tabItem { Label(AppTab.search.title, systemImage: AppTab.search.systemImageName) }
				.tag(AppTab.search)

			NavigationStack { MembersView() }
				.tabItem { Label(AppTab.members.title, systemImage: AppTab.members.systemImageName) }
				.tag(AppTab.members)

			ExpendituresView()
				.tabItem { Label(AppTab.expenditures.title, systemImage: AppTab.expenditures.systemImageName) }
				.tag(AppTab.expenditures)
		}
		.safeAreaInset(edge: .bottom) { offlineBanner }
	}

	// MARK: - iPad layout (regular size class)

	private var iPadLayout: some View {
		NavigationSplitView {
			List {
				ForEach(AppTab.allCases) { tab in
					Button {
						router.selectedTab = tab
					} label: {
						Label(tab.title, systemImage: tab.systemImageName)
							.foregroundStyle(router.selectedTab == tab ? Color.accentColor : .primary)
					}
					.listRowBackground(
						router.selectedTab == tab
							? Color.accentColor.opacity(0.12)
							: Color.clear
					)
				}
			}
			.navigationTitle("epac")
		} detail: {
			// Keep all three detail views alive with opacity rather than a switch,
			// so each view's NavigationStack retains its push state when the user
			// navigates between sidebar items and returns.
			ZStack {
				calendarStack
					.opacity(router.selectedTab == .sittingCalendar ? 1 : 0)
				SearchView()
					.opacity(router.selectedTab == .search ? 1 : 0)
				NavigationStack { MembersView() }
					.opacity(router.selectedTab == .members ? 1 : 0)
				ExpendituresView()
					.opacity(router.selectedTab == .expenditures ? 1 : 0)
			}
		}
		.safeAreaInset(edge: .bottom) { offlineBanner }
	}

	// MARK: - Shared calendar navigation stack

	private var calendarStack: some View {
		NavigationStack {
			SittingCalendarView(selectedDate: $viewModel.selectedDate)
				.environmentObject(fetch)
				.navigationDestination(item: $viewModel.selectedHansard) { hansard in
					SittingView(hansard: hansard, selectedSubject: $viewModel.selectedSubject)
						.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
						.navigationDestination(item: $viewModel.selectedSubject) { subject in
							SpeechView(hansard: hansard, subject: subject)
								.onDisappear { Log.debug("onDisappear") }
						}
				}
				.navigationDestination(item: $viewModel.nonSittingDate) { date in
					NonSittingDayView(date: date)
				}
				.onChange(of: viewModel.selectedDate) { _, newValue in
					viewModel.onSelectedDateChanged(to: newValue, modelContext: modelContext, fetch: fetch)
				}
		}
	}
}


