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
import CoreSpotlight

struct ContentView: View {
	@Environment(\.modelContext) var modelContext
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	var fetch: Fetch
	@Environment(NotificationManager.self) private var notificationManager
	@State private var viewModel = ContentViewModel()
	@State private var router = NavigationRouter()
	@State private var networkMonitor = NetworkMonitor()
	@State private var showMyMPSetup = PostalCodeViewModel.savedRidingName == nil
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
			router.selectedTab = .parliament
			notificationManager.clearPendingDate()
		}
		.onContinueUserActivity(CSSearchableItemActionType) { activity in
			guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
			if let memberID = SpotlightIndexer.memberID(from: id) {
				if let match = members.first(where: { $0.memberID == memberID }) {
					router.selectedMember = match
					router.selectedTab = .members
				}
			}
		}
		.task {
			networkMonitor.start()
			await viewModel.downloadInitialData(members: members, constituencies: constituencies, modelContext: modelContext, fetch: fetch)
			// Index data into Spotlight after the initial sync so results are available system-wide.
			let entries = SpotlightIndexer.makeEntries(from: members)
			await SpotlightIndexer.indexMembers(entries)
			// Request notification permission after initial content is loaded,
			// so the system prompt appears in context rather than at cold launch.
			await notificationManager.requestAuthorization()
		}
		.sheet(isPresented: $showMyMPSetup) {
			PostalCodeSetupView { showMyMPSetup = false }
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
			.background(Color.appWarning)
		}
	}

	// MARK: - Phone layout (compact size class)

	private var phoneLayout: some View {
		TabView(selection: $router.selectedTab) {
			HomeFeedView()
				.tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImageName) }
				.tag(AppTab.home)

			parliamentStack
				.tabItem { Label(AppTab.parliament.title, systemImage: AppTab.parliament.systemImageName) }
				.tag(AppTab.parliament)

			membersStack
				.tabItem { Label(AppTab.members.title, systemImage: AppTab.members.systemImageName) }
				.tag(AppTab.members)

			AccountabilityHubView()
				.tabItem { Label(AppTab.accountability.title, systemImage: AppTab.accountability.systemImageName) }
				.tag(AppTab.accountability)

			SearchView()
				.tabItem { Label(AppTab.search.title, systemImage: AppTab.search.systemImageName) }
				.tag(AppTab.search)
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
			// Keep all detail views alive with opacity rather than a switch,
			// so each view's NavigationStack retains its push state when the user
			// navigates between sidebar items and returns.
			ZStack {
				HomeFeedView()
					.opacity(router.selectedTab == .home ? 1 : 0)
				parliamentStack
					.opacity(router.selectedTab == .parliament ? 1 : 0)
				membersStack
					.opacity(router.selectedTab == .members ? 1 : 0)
				AccountabilityHubView()
					.opacity(router.selectedTab == .accountability ? 1 : 0)
				SearchView()
					.opacity(router.selectedTab == .search ? 1 : 0)
			}
		}
		.safeAreaInset(edge: .bottom) { offlineBanner }
	}

	// MARK: - Members navigation stack

	private var membersStack: some View {
		NavigationStack {
			MembersView()
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							showMyMPSetup = true
						} label: {
							Label(NSLocalizedString("riding.myMP.toolbarLabel", comment: ""), systemImage: "mappin.and.ellipse")
						}
						.accessibilityLabel(NSLocalizedString("riding.setup.navTitle", comment: ""))
					}
				}
				.navigationDestination(item: $router.selectedMember) { member in
					MemberProfileView(member: member)
				}
		}
	}

	// MARK: - Parliament navigation stack

	private var parliamentStack: some View {
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


