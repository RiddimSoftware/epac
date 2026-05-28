//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import CoreSpotlight
import Foundation
import Observation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
	private typealias CustomSchemeHandler = (URL) -> Void
	private typealias UniversalLinkHandler = ([String], URL) -> Void

	private enum AppPreviewDefaults {
		static let followedMemberID = 1422
	}

	private enum Layout {
		static let offlineBannerSpacing: CGFloat = 10
		static let offlineBannerVerticalPadding: CGFloat = 10
		static let sidebarSelectionOpacity = 0.16
	}

	@Environment(\.modelContext) var modelContext
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.scenePhase) private var scenePhase
	var fetch: Fetch
	var hansardRepository: any HansardRepository
	var appDelegate: AppDelegate
	@State private var viewModel = ContentViewModel()
	@State private var router = NavigationRouter()
	@State private var networkMonitor = NetworkMonitor()
	@State private var showMyMPSetup = !AppRuntime.shouldSuppressFirstLaunchSurfacesInTests && !AppEnvironment.isMarketingCaptureMode && UserDefaults.standard.bool(forKey: "epac.onboarding.completed") && PostalCodeViewModel.savedRidingName == nil
	@State private var showOnboarding = !AppRuntime.shouldSuppressFirstLaunchSurfacesInTests && !AppEnvironment.isMarketingCaptureMode && !UserDefaults.standard.bool(forKey: "epac.onboarding.completed")
	@State private var showWhatsNew = false

	init(fetch: Fetch, hansardRepository: any HansardRepository, appDelegate: AppDelegate) {
		self.fetch = fetch
		self.hansardRepository = hansardRepository
		self.appDelegate = appDelegate
		if AppEnvironment.isAppPreviewMode {
			Self.configureAppPreviewMode()
		}
	}

	private static func configureAppPreviewMode() {
		let defaults = UserDefaults.standard
		defaults.set(true, forKey: "epac.onboarding.completed")
		defaults.set(AppEnvironment.appPreviewPostalCode, forKey: "epac.myMP.postalCode")
		defaults.set("Fleetwood-Port Kells", forKey: "epac.myMP.ridingName")
		defaults.set("Gurbux Saini", forKey: "epac.myMP.memberName")
		if let followedMembers = try? JSONEncoder().encode([AppPreviewDefaults.followedMemberID: FollowPreferences()]) {
			defaults.set(followedMembers, forKey: "epac.followedMembers")
		}
		let followedBill = BillFollowState(
			lastKnownStatus: BillStatus.inProgress.rawValue,
			lastKnownStage: "Second reading",
			followedAt: Date()
		)
		if let followedBills = try? JSONEncoder().encode(["C-226": followedBill]) {
			defaults.set(followedBills, forKey: "epac.followedBills")
		}
	}

	var body: some View {
		Group {
			if AppEnvironment.isAppStoreScreenshotMode {
				AppStoreScreenshotShowcaseView()
			} else if AppEnvironment.isAppPreviewMode {
				AppPreviewVideoView()
			} else if horizontalSizeClass == .compact {
				phoneLayout
			} else {
				iPadLayout
			}
		}
		.environmentObject(fetch)
		.environment(\.hansardRepository, hansardRepository)
		.environment(router)
		.environment(networkMonitor)
		.onOpenURL { url in
			handleOpenURL(url)
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
			// Seed the in-memory SwiftData store with a real Hansard XML when
			// EPAC_EVIDENCE_MODE=1 is set, so Parliament-tab regression captures
			// land on populated state instead of empty placeholders. See
			// EvidenceFixtureSeed for the fixture selection logic.
			await EvidenceFixtureSeed.seedIfNeeded(via: fetch)
		}
		.task {
			guard !AppRuntime.isRunningTests, !AppEnvironment.isMarketingCaptureMode else { return }
			registerMacCommands()
			// Wire the router to the AppDelegate so Home Screen Quick Actions
			// (UIApplicationShortcutItem) are forwarded to the navigation layer.
			appDelegate.router = router
			networkMonitor.start()
			showWhatsNew = WhatsNewManager.shared.shouldShow()
			// Fetch members and constituencies inside the task so the @Query
			// table scans don't block the main thread before first frame.
			let members = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
			let constituencies = (try? modelContext.fetch(FetchDescriptor<Constituency>())) ?? []
			await viewModel.downloadInitialData(members: members, constituencies: constituencies, modelContext: modelContext, fetch: fetch)
			// Seed Cabinet from the bundled snapshot. Bundled JSON ships with the
			// app, so this is offline-safe; backgroundRefresh re-seeds on subsequent
			// launches to absorb shipped Cabinet shuffles.
			try? await fetch.loadCabinetPositions()
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
		.onAppear {
			registerMacCommands()
		}
		.sheet(isPresented: $showOnboarding) {
			OnboardingView {
				showOnboarding = false
				// Postal code may have been set during onboarding.
				showMyMPSetup = false
			}
			.interactiveDismissDisabled()
		}
		.regularSizeClassFormSheet(isPresented: $showMyMPSetup) {
			PostalCodeSetupView { showMyMPSetup = false }
		}
		.onChange(of: router.pendingShowPostalCodeSetup) { _, pending in
			if pending {
				showMyMPSetup = true
				router.pendingShowPostalCodeSetup = false
			}
		}
		.onChange(of: router.pendingQuickAction) { _, action in
			guard let action else { return }
			handleQuickAction(action)
			router.pendingQuickAction = nil
		}
		.regularSizeClassFormSheet(isPresented: $showWhatsNew) {
			WhatsNewView { showWhatsNew = false }
				.presentationDetents([.medium])
				.presentationDragIndicator(.visible)
		}
	}

	// MARK: - Offline banner

	@ViewBuilder
	private var offlineBanner: some View {
		if !networkMonitor.isConnected {
			HStack(spacing: Layout.offlineBannerSpacing) {
				Image(systemName: "wifi.slash")
				Text("You're offline. Showing cached content.")
					.font(.footnote)
				Spacer()
			}
			.foregroundStyle(.white)
			.padding(.horizontal)
			.padding(.vertical, Layout.offlineBannerVerticalPadding)
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
							.frame(maxWidth: .infinity, alignment: .leading)
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.listRowBackground(router.selectedTab == tab ? Color.accentColor.opacity(Layout.sidebarSelectionOpacity) : Color.clear)
					.accessibilityAddTraits(router.selectedTab == tab ? [.isSelected] : [])
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
		#if targetEnvironment(macCatalyst)
		.toolbar { macToolbarItems }
		#endif
		.safeAreaInset(edge: .bottom) { offlineBanner }
	}

	#if targetEnvironment(macCatalyst)
	@ToolbarContentBuilder
	private var macToolbarItems: some ToolbarContent {
		ToolbarItemGroup(placement: .primaryAction) {
			ForEach(AppTab.allCases) { tab in
				Button {
					router.selectedTab = tab
				} label: {
					Label(tab.title, systemImage: tab.systemImageName)
				}
				.help(tab.plainTitle)
			}
		}
	}
	#endif

	private func registerMacCommands() {
		#if targetEnvironment(macCatalyst)
		MacCommandCenter.shared.selectTab = { tab in
			router.selectedTab = tab
		}
		MacCommandCenter.shared.refresh = {
			Task { @MainActor in
				let members = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
				let constituencies = (try? modelContext.fetch(FetchDescriptor<Constituency>())) ?? []
				await viewModel.downloadInitialData(members: members, constituencies: constituencies, modelContext: modelContext, fetch: fetch)
				if router.selectedTab == .parliament, let selectedDate = viewModel.selectedDate {
					viewModel.onSelectedDateChanged(to: selectedDate)
				}
			}
		}
		MacCommandCenter.shared.share = {
			#if canImport(UIKit)
			UIPasteboard.general.url = URL(string: "https://epac.riddimsoftware.com")
			#endif
		}
		#endif
	}

	// MARK: - Members navigation stack

	private var membersStack: some View {
		MembersTabRoot(selectedMember: $router.selectedMember) {
			showMyMPSetup = true
		}
	}

	// MARK: - Deep-link navigation helpers

	/// Routes all incoming URLs. Custom scheme `cabinetdoor://` is handled first;
	/// Universal Links (https://epac.riddimsoftware.com/...) use path-based routing;
	/// legacy query-parameter links (/app?date=...) fall through to ContentViewModel.
	private func handleOpenURL(_ url: URL) {
		guard let scheme = url.scheme?.lowercased() else { return }
		if scheme == "cabinetdoor" || scheme == "epac" {
			handleCustomScheme(url)
		} else if scheme == "https" || scheme == "http" {
			handleUniversalLink(url)
		}
		// Other schemes (mailto:, etc.) are ignored.
	}

	private func handleCustomScheme(_ url: URL) {
		// cabinetdoor://member/[memberID]
		// cabinetdoor://vote/[voteID]  → switches to accountability tab
		// cabinetdoor://sitting/[yyyy-MM-dd]  → Parliament tab, first sitting day
		let host = url.host?.lowercased() ?? ""
		customSchemeHandlers[host]?(url)
	}

	/// Handles Universal Links from epac.riddimsoftware.com.
	/// Each path pattern maps to a specific in-app destination; unrecognised paths fall back to Home.
	private func handleUniversalLink(_ url: URL) {
		let segments = url.pathComponents.filter { $0 != "/" }
		let route = segments.first ?? "app"

		guard let handler = universalLinkHandlers[route] else {
			router.selectedTab = .home
			return
		}

		handler(segments, url)
	}

	private var customSchemeHandlers: [String: CustomSchemeHandler] {
		[
			"member": handleMemberCustomScheme,
			"vote": handleVoteCustomScheme,
			"sitting": handleSittingCustomScheme,
			"event": handleSittingCustomScheme
		]
	}

	private var universalLinkHandlers: [String: UniversalLinkHandler] {
		[
			"member": handleMemberUniversalLink,
			"vote": handleVoteUniversalLink,
			"bill": handleBillUniversalLink,
			"sitting": handleSittingUniversalLink,
			"speech": handleSpeechUniversalLink,
			"topic": handleTopicUniversalLink,
			"topics": handleTopicUniversalLink,
			"riding": handleRidingUniversalLink,
			"ridings": handleRidingUniversalLink,
			"setup": handleSetupUniversalLink,
			"app": handleAppUniversalLink
		]
	}

	private func handleMemberCustomScheme(_ url: URL) {
		let pathID = url.pathComponents.dropFirst().first.flatMap { Int($0) }
		if let id = pathID { navigateToMember(memberID: id) }
	}

	private func handleVoteCustomScheme(_ _: URL) {
		router.selectedTab = .accountability
	}

	private func handleSittingCustomScheme(_ url: URL) {
		// Rebuild as a path-based URL so ContentViewModel's sitting parser can consume it.
		let host = url.host?.lowercased() ?? ""
		let dateStr = url.pathComponents.dropFirst().first ?? ""
		if let rebuilt = URL(string: "cabinetdoor:///\(host)/\(dateStr)") {
			viewModel.onOpenURL(rebuilt, modelContext: modelContext, fetch: fetch)
		}
		router.selectedTab = .parliament
	}

	private func handleMemberUniversalLink(segments: [String], url _: URL) {
		// /member/[member-id] → MP profile
		if let idStr = segments.dropFirst().first, let id = Int(idStr) {
			navigateToMember(memberID: id)
		}
	}

	private func handleVoteUniversalLink(segments: [String], url _: URL) {
		// /vote/[parliament]-[session]/[number] → Search tab pre-filled
		let voteRef = segments.dropFirst().joined(separator: "/")
		if !voteRef.isEmpty { router.pendingSearchQuery = voteRef }
		router.selectedTab = .search
	}

	private func handleBillUniversalLink(segments: [String], url _: URL) {
		// /bill/[bill-number] e.g. /bill/C-50 → Search tab pre-filled
		if let billNumber = segments.dropFirst().first {
			router.pendingSearchQuery = billNumber
		}
		router.selectedTab = .search
	}

	private func handleSittingUniversalLink(segments: [String], url: URL) {
		// /sitting/[date] → Parliament tab (date routing in ContentViewModel)
		viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
		router.selectedTab = .parliament
	}

	private func handleSpeechUniversalLink(segments _: [String], url _: URL) {
		// Generic speech web share pages land on Parliament; specific speech
		// deep-links remain handled by ContentViewModel's legacy /app format.
		router.selectedTab = .parliament
	}

	private func handleTopicUniversalLink(segments: [String], url _: URL) {
		// /topic/[topic-slug] and website /topics/[topic-slug].html → Search tab pre-filled
		if let slug = segments.dropFirst().first {
			router.pendingSearchQuery = searchQuery(fromWebSlug: slug)
			router.selectedTab = .search
		}
	}

	private func handleRidingUniversalLink(segments: [String], url _: URL) {
		// /riding/[riding-slug] and website /ridings/[riding-slug].html → Search tab pre-filled
		if let slug = segments.dropFirst().first {
			router.pendingSearchQuery = searchQuery(fromWebSlug: slug)
			router.selectedTab = .search
		}
	}

	private func handleSetupUniversalLink(segments _: [String], url _: URL) {
		// /setup/postal-code → postal code setup sheet on Home tab
		router.pendingShowPostalCodeSetup = true
		router.selectedTab = .home
	}

	private func handleAppUniversalLink(segments _: [String], url: URL) {
		if let (pathURL, _) = encodedPathUniversalLink(from: url) {
			handleUniversalLink(pathURL)
			return
		}
		// Legacy query-parameter format: /app?date=...&subjectID=...
		viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
	}

	private func encodedPathUniversalLink(from url: URL) -> (url: URL, path: String)? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
		      path.hasPrefix("/") else {
			return nil
		}

		var rebuilt = URLComponents()
		rebuilt.scheme = "https"
		rebuilt.host = "epac.riddimsoftware.com"
		let pathWithoutFragment = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"
		rebuilt.path = pathWithoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"

		if let queryStart = pathWithoutFragment.firstIndex(of: "?") {
			let query = pathWithoutFragment[pathWithoutFragment.index(after: queryStart)...]
			rebuilt.query = String(query)
		}

		guard let url = rebuilt.url else { return nil }
		return (url, path)
	}

	private func searchQuery(fromWebSlug slug: String) -> String {
		slug
			.replacingOccurrences(of: ".html", with: "")
			.replacingOccurrences(of: "-", with: " ")
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

	// MARK: - Home Screen Quick Actions (EPAC-351)

	/// Routes a Home Screen Quick Action to the correct tab and state.
	private func handleQuickAction(_ action: QuickAction) {
		switch action {
		case .todayInParliament:
			// Navigate to Parliament tab calendar.
			router.selectedTab = .parliament

		case .findMyMP:
			// If the user has not set up their MP yet, show the postal code sheet;
			// otherwise navigate to the Home tab where the My MP section is prominent.
			if PostalCodeViewModel.savedRidingName == nil {
				router.pendingShowPostalCodeSetup = true
				router.selectedTab = .home
			} else {
				router.selectedTab = .home
			}

		case .searchDebates:
			// Navigate to Search tab; SearchView auto-focuses the search bar on appear.
			router.selectedTab = .search
		}
	}

	// MARK: - Parliament navigation stack

	private var parliamentStack: some View {
		NavigationStack {
			SittingCalendarView(
				selectedDate: $viewModel.selectedDate,
				pendingInterventionID: $viewModel.pendingInterventionID
			)
			.environmentObject(fetch)
			.navigationDestination(item: $viewModel.selectedHansard) { hansard in
				hansardDestination(hansard)
			}
			.navigationDestination(item: $viewModel.selectedSittingDate) { date in
				sittingLoaderDestination(date)
			}
			.navigationDestination(item: $viewModel.nonSittingDate) { date in
				NonSittingDayView(date: date)
			}
			.onChange(of: viewModel.selectedDate) { _, newValue in
				viewModel.onSelectedDateChanged(to: newValue)
			}
		}
	}

	private func hansardDestination(_ hansard: Hansard) -> some View {
		SittingView(hansard: hansard, selectedSubject: $viewModel.selectedSubject)
			.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
			.navigationDestination(item: $viewModel.selectedSubject) { subject in
				SpeechView(hansard: hansard, subject: subject)
					.onDisappear { Log.debug("onDisappear") }
			}
	}

	private func sittingLoaderDestination(_ date: Date) -> some View {
		let interventionID = viewModel.pendingInterventionID
		viewModel.pendingInterventionID = nil
		return SittingLoaderView(
			date: date,
			selectedSubject: $viewModel.selectedSubject,
			initialInterventionID: interventionID
		)
	}
}

// MARK: - App Store screenshot mode

private enum AppStoreScreenshotSpec {
	static let firstPageIndex = 0
	static let lastPageIndex = 5
	static let overviewAccent: (red: Double, green: Double, blue: Double) = (0.0, 0.44, 0.89)
	static let lobbyingAccent: (red: Double, green: Double, blue: Double) = (0.0, 0.64, 0.69)
	static let backgroundAccentOpacity = 0.28
	static let pageVerticalSpacing: CGFloat = 20
	static let titleVerticalSpacing: CGFloat = 10
	static let headlineFontSize: CGFloat = 31
	static let headlineMinimumScaleFactor: CGFloat = 0.66
	static let headlineLineLimit = 3
	static let subtitleFontSize: CGFloat = 13
	static let subtitleLineLimit = 3
	static let titleHorizontalPadding: CGFloat = 28
	static let showcaseHorizontalPadding: CGFloat = 20
	static let bottomSpacerMinLength: CGFloat = 18
	static let pageTopPadding: CGFloat = 42
	static let phoneContentSpacing: CGFloat = 18
	static let votePillRowSpacing: CGFloat = 14
	static let voteMemberNameFontSize: CGFloat = 30
	static let avatarOpacity = 0.18
	static let avatarMonogramFontSize: CGFloat = 25
	static let memberDetailSpacing: CGFloat = 6
	static let memberNameFontSize: CGFloat = 23
	static let memberRidingFontSize: CGFloat = 15
	static let partyPillFontSize: CGFloat = 12
	static let partyPillHorizontalPadding: CGFloat = 12
	static let partyPillVerticalPadding: CGFloat = 6
	static let partyPillOpacity = 0.16
	static let billTitleFontSize: CGFloat = 21
	static let billStageSpacing: CGFloat = 14
	static let contactFieldFontSize: CGFloat = 16
	static let contactSubjectFontSize: CGFloat = 19
	static let contactBodyFontSize: CGFloat = 17
	static let contactBodyLineSpacing: CGFloat = 5
	static let contactButtonFontSize: CGFloat = 18
	static let contactButtonVerticalPadding: CGFloat = 16
	static let phoneContentPadding: CGFloat = 18
	static let phoneShadowOpacity = 0.16
	static let phoneShadowRadius: CGFloat = 16
	static let phoneShadowYOffset: CGFloat = 10
	static let helperSpacing: CGFloat = 12
	static let headerIconFontSize: CGFloat = 18
	static let headerFontSize: CGFloat = 19
	static let compactMinimumScaleFactor: CGFloat = 0.72
	static let detailMinimumScaleFactor: CGFloat = 0.75
	static let metricRowSpacing: CGFloat = 10
	static let metricLabelFontSize: CGFloat = 12
	static let metricValueFontSize: CGFloat = 18
	static let metricValueLineLimit = 2
	static let metricValueMinimumScaleFactor: CGFloat = 0.7
	static let detailLineLimit = 2
	static let metricRowPadding: CGFloat = 12
	static let metricRowCornerRadius: CGFloat = 14
	static let activityAccentCornerRadius: CGFloat = 7
	static let activityTextSpacing: CGFloat = 5
	static let activityTitleFontSize: CGFloat = 17
	static let activityDetailFontSize: CGFloat = 13
	static let activityRowPadding: CGFloat = 12
	static let activityRowCornerRadius: CGFloat = 18
	static let votePillInnerSpacing: CGFloat = 6
	static let voteCountFontSize: CGFloat = 22
	static let votePillOpacity = 0.14
	static let votePillCornerRadius: CGFloat = 16
	static let stageCurrentFontSize: CGFloat = 14
	static let stageCurrentHorizontalPadding: CGFloat = 10
	static let stageCurrentVerticalPadding: CGFloat = 5
	static let sourceBadgeFontSize: CGFloat = 11
	static let sourceBadgeHorizontalPadding: CGFloat = 12
	static let sourceBadgeVerticalPadding: CGFloat = 8

	// iPad two-column layout
	static let iPadHeadlineFontSize: CGFloat = 44
	static let iPadSubtitleFontSize: CGFloat = 18
	static let iPadColumnSpacing: CGFloat = 40
	static let iPadContentPadding: CGFloat = 48
	static let iPadTopPadding: CGFloat = 64
	static let iPadPhoneFrameMaxWidth: CGFloat = 420
}

private struct AppStoreScreenshotShowcaseView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@State private var selection = Self.initialSelection()

	private var isIPad: Bool { horizontalSizeClass == .regular }

	private static func initialSelection() -> Int {
		let arguments = ProcessInfo.processInfo.arguments
		guard let index = arguments.firstIndex(of: "-AppStoreScreenshotPage"),
			  let valueIndex = arguments.index(index, offsetBy: 1, limitedBy: arguments.endIndex),
			  valueIndex < arguments.endIndex,
			  let page = Int(arguments[valueIndex]) else {
			return AppStoreScreenshotSpec.firstPageIndex
		}

		return min(max(page, AppStoreScreenshotSpec.firstPageIndex), AppStoreScreenshotSpec.lastPageIndex)
	}

	private var pages: [AppStoreScreenshotPage] {
		[
			.init(
				headline: t("appStore.screenshot.page1.headline"),
				subtitle: t("appStore.screenshot.page1.subtitle"),
				accent: Color(
					red: AppStoreScreenshotSpec.overviewAccent.red,
					green: AppStoreScreenshotSpec.overviewAccent.green,
					blue: AppStoreScreenshotSpec.overviewAccent.blue
				),
				kind: .overview
			),
			.init(
				headline: t("appStore.screenshot.page2.headline"),
				subtitle: t("appStore.screenshot.page2.subtitle"),
				accent: .appPositive,
				kind: .votes
			),
			.init(
				headline: t("appStore.screenshot.page3.headline"),
				subtitle: t("appStore.screenshot.page3.subtitle"),
				accent: Color.party(.liberal),
				kind: .myMP
			),
			.init(
				headline: t("appStore.screenshot.page4.headline"),
				subtitle: t("appStore.screenshot.page4.subtitle"),
				accent: Color.billStatus(.inProgress),
				kind: .bill
			),
			.init(
				headline: t("appStore.screenshot.page5.headline"),
				subtitle: t("appStore.screenshot.page5.subtitle"),
				accent: Color(
					red: AppStoreScreenshotSpec.lobbyingAccent.red,
					green: AppStoreScreenshotSpec.lobbyingAccent.green,
					blue: AppStoreScreenshotSpec.lobbyingAccent.blue
				),
				kind: .lobbying
			),
			.init(
				headline: t("appStore.screenshot.page6.headline"),
				subtitle: t("appStore.screenshot.page6.subtitle"),
				accent: .appWarning,
				kind: .contact
			)
		]
	}

	private func t(_ key: String) -> String {
		NSLocalizedString(key, comment: "")
	}

	var body: some View {
		Group {
			if isIPad {
				iPadBody
			} else {
				phoneBody
			}
		}
		.dynamicTypeSize(.large)
		.preferredColorScheme(.light)
	}

	private var phoneBody: some View {
		TabView(selection: $selection) {
			ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
				AppStoreScreenshotPageView(page: page, isIPad: false)
					.tag(index)
			}
		}
		.tabViewStyle(.page(indexDisplayMode: .never))
	}

	private var iPadBody: some View {
		let page = pages[selection]
		return AppStoreScreenshotPageView(page: page, isIPad: true)
	}
}

private struct AppStoreScreenshotPage {
	enum Kind {
		case overview
		case votes
		case myMP
		case bill
		case lobbying
		case contact
	}

	let headline: String
	let subtitle: String
	let accent: Color
	let kind: Kind
}

private struct AppStoreScreenshotPageView: View {
	let page: AppStoreScreenshotPage
	var isIPad = false

	private func t(_ key: String) -> String {
		NSLocalizedString(key, comment: "")
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			LinearGradient(
				colors: [
					page.accent.opacity(AppStoreScreenshotSpec.backgroundAccentOpacity),
					Color(UIColor.systemBackground),
					Color(UIColor.secondarySystemBackground)
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
			.ignoresSafeArea()

			if isIPad {
				iPadContent
			} else {
				phoneContent
			}
		}
	}

	private var phoneContent: some View {
		VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.pageVerticalSpacing) {
			titleSection(headlineSize: AppStoreScreenshotSpec.headlineFontSize, subtitleSize: AppStoreScreenshotSpec.subtitleFontSize)
				.padding(.horizontal, AppStoreScreenshotSpec.titleHorizontalPadding)

			showcaseContent
				.padding(.horizontal, AppStoreScreenshotSpec.showcaseHorizontalPadding)

			Spacer(minLength: AppStoreScreenshotSpec.bottomSpacerMinLength)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(.top, AppStoreScreenshotSpec.pageTopPadding)
	}

	private var iPadContent: some View {
		HStack(alignment: .top, spacing: AppStoreScreenshotSpec.iPadColumnSpacing) {
			VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.pageVerticalSpacing) {
				titleSection(headlineSize: AppStoreScreenshotSpec.iPadHeadlineFontSize, subtitleSize: AppStoreScreenshotSpec.iPadSubtitleFontSize)
				Spacer()
			}
			.frame(maxWidth: .infinity, alignment: .topLeading)

			showcaseContent
				.frame(maxWidth: AppStoreScreenshotSpec.iPadPhoneFrameMaxWidth)
		}
		.padding(AppStoreScreenshotSpec.iPadContentPadding)
		.padding(.top, AppStoreScreenshotSpec.iPadTopPadding)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}

	private func titleSection(headlineSize: CGFloat, subtitleSize: CGFloat) -> some View {
		VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.titleVerticalSpacing) {
			Text(page.headline)
				.font(.system(size: headlineSize, weight: .heavy, design: .rounded))
				.foregroundStyle(.primary)
				.minimumScaleFactor(AppStoreScreenshotSpec.headlineMinimumScaleFactor)
				.lineLimit(AppStoreScreenshotSpec.headlineLineLimit)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityIdentifier("appStoreScreenshotHeadline")

			Text(page.subtitle)
				.font(.system(size: subtitleSize, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
				.lineLimit(AppStoreScreenshotSpec.subtitleLineLimit)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	@ViewBuilder
	private var showcaseContent: some View {
		switch page.kind {
		case .overview:
			phoneFrame {
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
					header(t("appStore.screenshot.overview.header"), systemImage: "building.columns.fill")
					metricGrid([
						(t("appStore.screenshot.overview.metric1.label"), "C-226", t("appStore.screenshot.overview.metric1.detail")),
						(t("appStore.screenshot.overview.metric2.label"), t("appStore.screenshot.overview.metric2.value"), t("appStore.screenshot.overview.metric2.detail")),
						(t("appStore.screenshot.overview.metric3.label"), t("appStore.screenshot.overview.metric3.value"), t("appStore.screenshot.overview.metric3.detail"))
					])
					activityRow(title: t("appStore.screenshot.overview.row1.title"), detail: t("appStore.screenshot.overview.row1.detail"), color: page.accent)
					activityRow(title: t("appStore.screenshot.overview.row2.title"), detail: t("appStore.screenshot.overview.row2.detail"), color: Color.party(.conservative))
					sourceBadge(t("appStore.screenshot.overview.source"))
				}
			}
		case .votes:
			phoneFrame {
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
					header(t("appStore.screenshot.votes.header"), systemImage: "checklist.checked")
					Text("Gurbux Saini")
						.font(.system(size: AppStoreScreenshotSpec.voteMemberNameFontSize, weight: .bold, design: .rounded))
					Text(t("appStore.screenshot.votes.memberDetail"))
						.font(.system(size: AppStoreScreenshotSpec.metricValueFontSize, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
					HStack(spacing: AppStoreScreenshotSpec.votePillRowSpacing) {
						votePill(t("appStore.screenshot.votes.yea"), count: "42", color: .appPositive)
						votePill(t("appStore.screenshot.votes.nay"), count: "11", color: .appDestructive)
						votePill(t("appStore.screenshot.votes.paired"), count: "2", color: .appWarning)
					}
					activityRow(title: t("appStore.screenshot.votes.row1.title"), detail: t("appStore.screenshot.votes.row1.detail"), color: .appPositive)
					activityRow(title: t("appStore.screenshot.votes.row2.title"), detail: t("appStore.screenshot.votes.row2.detail"), color: .appDestructive)
					sourceBadge(t("appStore.screenshot.votes.source"))
				}
			}
		case .myMP:
			phoneFrame {
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
					header(t("appStore.screenshot.myMP.header"), systemImage: "person.crop.circle.fill")
					HStack(spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
						Circle()
							.fill(Color.party(.liberal).opacity(AppStoreScreenshotSpec.avatarOpacity))
							.frame(width: EpacMedia.screenshotAvatarSize, height: EpacMedia.screenshotAvatarSize)
							.overlay(Text("GS").font(.system(size: AppStoreScreenshotSpec.avatarMonogramFontSize, weight: .heavy, design: .rounded)).foregroundStyle(Color.party(.liberal)))
						VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.memberDetailSpacing) {
							Text("Gurbux Saini")
								.font(.system(size: AppStoreScreenshotSpec.memberNameFontSize, weight: .bold, design: .rounded))
							Text("Fleetwood-Port Kells")
								.font(.system(size: AppStoreScreenshotSpec.memberRidingFontSize, weight: .medium, design: .rounded))
								.foregroundStyle(.secondary)
							Text(t("appStore.screenshot.myMP.party"))
								.font(.system(size: AppStoreScreenshotSpec.partyPillFontSize, weight: .semibold, design: .rounded))
								.padding(.horizontal, AppStoreScreenshotSpec.partyPillHorizontalPadding)
								.padding(.vertical, AppStoreScreenshotSpec.partyPillVerticalPadding)
								.background(Color.party(.liberal).opacity(AppStoreScreenshotSpec.partyPillOpacity))
								.clipShape(Capsule())
						}
					}
					activityRow(title: t("appStore.screenshot.myMP.row1.title"), detail: t("appStore.screenshot.myMP.row1.detail"), color: Color.party(.liberal))
					activityRow(title: t("appStore.screenshot.myMP.row2.title"), detail: t("appStore.screenshot.myMP.row2.detail"), color: Color.party(.conservative))
					activityRow(title: t("appStore.screenshot.myMP.row3.title"), detail: t("appStore.screenshot.myMP.row3.detail"), color: page.accent)
				}
			}
		case .bill:
			phoneFrame {
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
					header(t("appStore.screenshot.bill.header"), systemImage: "doc.text.fill")
					Text(t("appStore.screenshot.bill.title"))
						.font(.system(size: AppStoreScreenshotSpec.billTitleFontSize, weight: .bold, design: .rounded))
						.fixedSize(horizontal: false, vertical: true)
					VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.billStageSpacing) {
						stage(t("appStore.screenshot.bill.stage1"), done: true)
						stage(t("appStore.screenshot.bill.stage2"), done: true)
						stage(t("appStore.screenshot.bill.stage3"), done: false, current: true)
						stage(t("appStore.screenshot.bill.stage4"), done: false)
						stage(t("appStore.screenshot.bill.stage5"), done: false)
					}
					sourceBadge(t("appStore.screenshot.bill.source"))
				}
			}
		case .lobbying:
			phoneFrame {
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
					header(t("appStore.screenshot.lobbying.header"), systemImage: "person.2.wave.2.fill")
					Text(t("appStore.screenshot.lobbying.title"))
						.font(.system(size: AppStoreScreenshotSpec.billTitleFontSize, weight: .bold, design: .rounded))
					activityRow(title: t("appStore.screenshot.lobbying.row1.title"), detail: t("appStore.screenshot.lobbying.row1.detail"), color: Color.party(.liberal))
					activityRow(title: t("appStore.screenshot.lobbying.row2.title"), detail: t("appStore.screenshot.lobbying.row2.detail"), color: page.accent)
					activityRow(title: t("appStore.screenshot.lobbying.row3.title"), detail: t("appStore.screenshot.lobbying.row3.detail"), color: .appWarning)
					sourceBadge(t("appStore.screenshot.lobbying.source"))
				}
			}
		case .contact:
			phoneFrame {
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.phoneContentSpacing) {
					header(t("appStore.screenshot.contact.header"), systemImage: "envelope.fill")
					VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.titleVerticalSpacing) {
						Text(t("appStore.screenshot.contact.subject"))
							.font(.system(size: AppStoreScreenshotSpec.contactFieldFontSize, weight: .semibold, design: .rounded))
							.foregroundStyle(.secondary)
						Text(t("appStore.screenshot.contact.subjectLine"))
							.font(.system(size: AppStoreScreenshotSpec.contactSubjectFontSize, weight: .bold, design: .rounded))
					}
					Divider()
					Text(t("appStore.screenshot.contact.body"))
						.font(.system(size: AppStoreScreenshotSpec.contactBodyFontSize, weight: .regular, design: .rounded))
						.lineSpacing(AppStoreScreenshotSpec.contactBodyLineSpacing)
					Text(t("appStore.screenshot.contact.send"))
						.font(.system(size: AppStoreScreenshotSpec.contactButtonFontSize, weight: .bold, design: .rounded))
						.frame(maxWidth: .infinity)
						.padding(.vertical, AppStoreScreenshotSpec.contactButtonVerticalPadding)
						.background(page.accent)
						.foregroundStyle(.white)
						.clipShape(RoundedRectangle(cornerRadius: AppStoreScreenshotSpec.activityRowCornerRadius, style: .continuous))
				}
			}
		}
	}

	private func phoneFrame<Content: View>(@ViewBuilder content: () -> Content) -> AnyView {
		AnyView(
			VStack(alignment: .leading, spacing: 0) {
				content()
					.padding(AppStoreScreenshotSpec.phoneContentPadding)
			}
			.frame(maxWidth: .infinity, minHeight: EpacMedia.screenshotPhoneMinHeight, alignment: .topLeading)
			.background(Color(UIColor.systemBackground))
			.clipShape(RoundedRectangle(cornerRadius: EpacMedia.screenshotPhoneCornerRadius, style: .continuous))
			.shadow(
				color: .black.opacity(AppStoreScreenshotSpec.phoneShadowOpacity),
				radius: AppStoreScreenshotSpec.phoneShadowRadius,
				y: AppStoreScreenshotSpec.phoneShadowYOffset
			)
		)
	}

	private func header(_ title: String, systemImage: String) -> AnyView {
		AnyView(
			HStack(spacing: AppStoreScreenshotSpec.helperSpacing) {
				Image(systemName: systemImage)
					.font(.system(size: AppStoreScreenshotSpec.headerIconFontSize, weight: .bold))
					.foregroundStyle(page.accent)
				Text(title)
					.font(.system(size: AppStoreScreenshotSpec.headerFontSize, weight: .heavy, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(AppStoreScreenshotSpec.compactMinimumScaleFactor)
				Spacer()
			}
		)
	}

	private func metricGrid(_ metrics: [(String, String, String)]) -> AnyView {
		AnyView(
			VStack(spacing: AppStoreScreenshotSpec.metricRowSpacing) {
				ForEach(metrics, id: \.0) { metric in
					HStack(spacing: AppStoreScreenshotSpec.metricRowSpacing) {
						Text(metric.0)
							.font(.system(size: AppStoreScreenshotSpec.metricLabelFontSize, weight: .semibold, design: .rounded))
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.minimumScaleFactor(AppStoreScreenshotSpec.compactMinimumScaleFactor)
							.frame(width: EpacMedia.screenshotMetricLabelWidth, alignment: .leading)
						Text(metric.1)
							.font(.system(size: AppStoreScreenshotSpec.metricValueFontSize, weight: .heavy, design: .rounded))
							.lineLimit(AppStoreScreenshotSpec.metricValueLineLimit)
							.minimumScaleFactor(AppStoreScreenshotSpec.metricValueMinimumScaleFactor)
							.frame(width: EpacMedia.screenshotMetricValueWidth, alignment: .leading)
						Text(metric.2)
							.font(.system(size: AppStoreScreenshotSpec.metricLabelFontSize, weight: .medium, design: .rounded))
							.foregroundStyle(.secondary)
							.lineLimit(AppStoreScreenshotSpec.detailLineLimit)
							.minimumScaleFactor(AppStoreScreenshotSpec.detailMinimumScaleFactor)
							.frame(maxWidth: .infinity, alignment: .leading)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(AppStoreScreenshotSpec.metricRowPadding)
					.background(Color(UIColor.secondarySystemBackground))
					.clipShape(RoundedRectangle(cornerRadius: AppStoreScreenshotSpec.metricRowCornerRadius, style: .continuous))
				}
			}
		)
	}

	private func activityRow(title: String, detail: String, color: Color) -> AnyView {
		AnyView(
			HStack(spacing: AppStoreScreenshotSpec.votePillRowSpacing) {
				RoundedRectangle(cornerRadius: AppStoreScreenshotSpec.activityAccentCornerRadius, style: .continuous)
					.fill(color)
					.frame(width: EpacMedia.screenshotAccentBarWidth, height: EpacMedia.screenshotAccentBarHeight)
				VStack(alignment: .leading, spacing: AppStoreScreenshotSpec.activityTextSpacing) {
					Text(title)
						.font(.system(size: AppStoreScreenshotSpec.activityTitleFontSize, weight: .bold, design: .rounded))
						.lineLimit(AppStoreScreenshotSpec.detailLineLimit)
						.minimumScaleFactor(AppStoreScreenshotSpec.detailMinimumScaleFactor)
					Text(detail)
						.font(.system(size: AppStoreScreenshotSpec.activityDetailFontSize, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.lineLimit(AppStoreScreenshotSpec.detailLineLimit)
						.minimumScaleFactor(AppStoreScreenshotSpec.detailMinimumScaleFactor)
				}
				Spacer()
			}
			.padding(AppStoreScreenshotSpec.activityRowPadding)
			.background(Color(UIColor.secondarySystemBackground))
			.clipShape(RoundedRectangle(cornerRadius: AppStoreScreenshotSpec.activityRowCornerRadius, style: .continuous))
		)
	}

	private func votePill(_ label: String, count: String, color: Color) -> AnyView {
		AnyView(
			VStack(spacing: AppStoreScreenshotSpec.votePillInnerSpacing) {
				Text(count)
					.font(.system(size: AppStoreScreenshotSpec.voteCountFontSize, weight: .heavy, design: .rounded))
				Text(label)
					.font(.system(size: AppStoreScreenshotSpec.partyPillFontSize, weight: .bold, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(AppStoreScreenshotSpec.compactMinimumScaleFactor)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, AppStoreScreenshotSpec.contactButtonVerticalPadding)
			.background(color.opacity(AppStoreScreenshotSpec.votePillOpacity))
			.foregroundStyle(color)
			.clipShape(RoundedRectangle(cornerRadius: AppStoreScreenshotSpec.votePillCornerRadius, style: .continuous))
		)
	}

	private func stage(_ label: String, done: Bool, current: Bool = false) -> AnyView {
		AnyView(
			HStack(spacing: AppStoreScreenshotSpec.helperSpacing) {
				Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
					.foregroundStyle(done ? .appPositive : current ? page.accent : .secondary)
				Text(label)
					.font(.system(size: AppStoreScreenshotSpec.activityTitleFontSize, weight: current ? .heavy : .semibold, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(AppStoreScreenshotSpec.detailMinimumScaleFactor)
				Spacer()
				if current {
					Text(t("appStore.screenshot.bill.current"))
						.font(.system(size: AppStoreScreenshotSpec.stageCurrentFontSize, weight: .bold, design: .rounded))
						.padding(.horizontal, AppStoreScreenshotSpec.stageCurrentHorizontalPadding)
						.padding(.vertical, AppStoreScreenshotSpec.stageCurrentVerticalPadding)
						.background(page.accent.opacity(AppStoreScreenshotSpec.votePillOpacity))
						.foregroundStyle(page.accent)
						.clipShape(Capsule())
				}
			}
		)
	}

	private func sourceBadge(_ text: String) -> AnyView {
		AnyView(
			Text(text)
				.font(.system(size: AppStoreScreenshotSpec.sourceBadgeFontSize, weight: .semibold, design: .rounded))
				.foregroundStyle(.secondary)
				.lineLimit(AppStoreScreenshotSpec.detailLineLimit)
				.multilineTextAlignment(.center)
				.padding(.horizontal, AppStoreScreenshotSpec.sourceBadgeHorizontalPadding)
				.padding(.vertical, AppStoreScreenshotSpec.sourceBadgeVerticalPadding)
				.background(Color(UIColor.tertiarySystemBackground))
				.clipShape(Capsule())
		)
	}
}
