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
	@Environment(\.scenePhase) private var scenePhase
	var fetch: Fetch
	@Environment(NotificationManager.self) private var notificationManager
	@State private var viewModel = ContentViewModel()
	@State private var router = NavigationRouter()
	@State private var networkMonitor = NetworkMonitor()
	@State private var showMyMPSetup = PostalCodeViewModel.savedRidingName == nil
	@State private var showOnboarding = !UserDefaults.standard.bool(forKey: "epac.onboarding.completed")
	@State private var showWhatsNew = false

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
			handleOpenURL(url)
		}
		.onChange(of: notificationManager.pendingDate) { _, date in
			guard let date else { return }
			let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
			viewModel.selectedDate = components
			viewModel.onSelectedDateChanged(to: components, modelContext: modelContext, fetch: fetch)
			router.selectedTab = .parliament
			notificationManager.clearPendingDate()
		}
		.onChange(of: notificationManager.pendingTopicId) { _, topicId in
			guard topicId != nil else { return }
			// Topic-debate notifications navigate to Accountability (Topics live there per ADR-001).
			router.selectedTab = .accountability
			notificationManager.clearPendingDate()
		}
		.onContinueUserActivity(CSSearchableItemActionType) { activity in
			guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
			if let memberID = SpotlightIndexer.memberID(from: id) {
				navigateToMember(memberID: memberID)
			}
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				checkPendingMemberNavigation()
			}
		}
		.task {
			networkMonitor.start()
			showWhatsNew = WhatsNewManager.shared.shouldShow()
			// Fetch members and constituencies inside the task so the @Query
			// table scans don't block the main thread before first frame.
			let members = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
			let constituencies = (try? modelContext.fetch(FetchDescriptor<Constituency>())) ?? []
			await viewModel.downloadInitialData(members: members, constituencies: constituencies, modelContext: modelContext, fetch: fetch)
			// Skip the permission request when onboarding is showing — the
			// onboarding flow presents a contextual prompt on screen 4. For
			// returning users (onboarding already completed) we request here as
			// before, so the prompt appears if they declined earlier and then
			// changed their mind in Settings.
			if !showOnboarding {
				await notificationManager.requestAuthorization()
			}
			// Snapshot lightweight name data on @MainActor (no imageData access).
			let nameEntries = members.map {
				MemberNameCache.Entry(memberID: $0.memberID, name: $0.name, lastName: $0.lastName)
			}
			let spotlightEntries = SpotlightIndexer.makeEntries(from: members)
			// Run caching and Spotlight index at utility priority so the main thread
			// stays free for keyboard animations immediately after first-launch sync.
			Task(priority: .utility) {
				MemberNameCache.shared.populate(entries: nameEntries)
				await SpotlightIndexer.indexMembers(spotlightEntries)
			}
		}
		.sheet(isPresented: $showOnboarding) {
			OnboardingView {
				showOnboarding = false
				// Postal code may have been set during onboarding.
				showMyMPSetup = false
			}
			.interactiveDismissDisabled()
		}
		.sheet(isPresented: $showMyMPSetup) {
			PostalCodeSetupView { showMyMPSetup = false }
		}
		.onChange(of: router.pendingShowPostalCodeSetup) { _, pending in
			if pending {
				showMyMPSetup = true
				router.pendingShowPostalCodeSetup = false
			}
		}
		.sheet(isPresented: $showWhatsNew) {
			WhatsNewView { showWhatsNew = false }
				.presentationDetents([.medium])
				.presentationDragIndicator(.visible)
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

	// MARK: - Deep-link navigation helpers

	/// Routes all incoming URLs. Custom scheme `cabinetdoor://` is handled first;
	/// Universal Links (https://epac.riddimsoftware.com/...) use path-based routing;
	/// legacy query-parameter links (/app?date=...) fall through to ContentViewModel.
	private func handleOpenURL(_ url: URL) {
		guard let scheme = url.scheme?.lowercased() else { return }
		if scheme == "cabinetdoor" {
			handleCustomScheme(url)
		} else if scheme == "https" || scheme == "http" {
			handleUniversalLink(url)
		}
		// Other schemes (mailto:, etc.) are ignored.
	}

	private func handleCustomScheme(_ url: URL) {
		// cabinetdoor://member/[memberID]
		// cabinetdoor://vote/[voteID]  → switches to accountability tab
		let host = url.host?.lowercased() ?? ""
		let pathID = url.pathComponents.dropFirst().first.flatMap { Int($0) }
		switch host {
		case "member":
			if let id = pathID { navigateToMember(memberID: id) }
		case "vote":
			router.selectedTab = .accountability
		default:
			break
		}
	}

	/// Handles Universal Links from epac.riddimsoftware.com.
	/// Each path pattern maps to a specific in-app destination; unrecognised paths fall back to Home.
	private func handleUniversalLink(_ url: URL) {
		let segments = url.pathComponents.filter { $0 != "/" }

		switch segments.first {
		case "member":
			// /member/[member-id] → MP profile
			if let idStr = segments.dropFirst().first, let id = Int(idStr) {
				navigateToMember(memberID: id)
			}
		case "vote":
			// /vote/[parliament]-[session]/[number] → Search tab pre-filled
			let voteRef = segments.dropFirst().joined(separator: "/")
			if !voteRef.isEmpty { router.pendingSearchQuery = voteRef }
			router.selectedTab = .search
		case "bill":
			// /bill/[bill-number] e.g. /bill/C-50 → Search tab pre-filled
			if let billNumber = segments.dropFirst().first {
				router.pendingSearchQuery = billNumber
				router.selectedTab = .search
			}
		case "sitting":
			// /sitting/[date] → Parliament tab (date routing in ContentViewModel)
			viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
			router.selectedTab = .parliament
		case "topic":
			// /topic/[topic-slug] → Search tab pre-filled
			if let slug = segments.dropFirst().first {
				router.pendingSearchQuery = slug.replacingOccurrences(of: "-", with: " ")
				router.selectedTab = .search
			}
		case "riding":
			// /riding/[riding-slug] → Search tab pre-filled (riding detail view planned)
			if let slug = segments.dropFirst().first {
				router.pendingSearchQuery = slug.replacingOccurrences(of: "-", with: " ")
				router.selectedTab = .search
			}
		case "setup":
			// /setup/postal-code → postal code setup sheet on Home tab
			router.pendingShowPostalCodeSetup = true
			router.selectedTab = .home
		case "app", nil:
			// Legacy query-parameter format: /app?date=...&subjectID=...
			viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
		default:
			// Home fallback for unrecognised paths — never crashes
			router.selectedTab = .home
		}
	}

	private func navigateToMember(memberID: Int) {
		if let match = try? modelContext.fetch(
			FetchDescriptor<ParliamentMember>(predicate: #Predicate { $0.memberID == memberID })
		).first {
			router.selectedMember = match
			router.selectedTab = .members
		}
	}

	private func checkPendingMemberNavigation() {
		let key = "pendingMemberID"
		guard let memberID = UserDefaults.standard.object(forKey: key) as? Int else { return }
		UserDefaults.standard.removeObject(forKey: key)
		navigateToMember(memberID: memberID)
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


