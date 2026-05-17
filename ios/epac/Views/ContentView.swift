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
	@Environment(\.modelContext) var modelContext
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.scenePhase) private var scenePhase
	var fetch: Fetch
	var appDelegate: AppDelegate
	@State private var viewModel = ContentViewModel()
	@State private var router = NavigationRouter()
	@State private var networkMonitor = NetworkMonitor()
	@State private var showMyMPSetup = !AppRuntime.isRunningTests && !AppEnvironment.isMarketingCaptureMode && PostalCodeViewModel.savedRidingName == nil
	@State private var showOnboarding = !AppRuntime.isRunningTests && !AppEnvironment.isMarketingCaptureMode && !UserDefaults.standard.bool(forKey: "epac.onboarding.completed")
	@State private var showWhatsNew = false
	private let recordWebToAppOpen = RecordWebToAppOpen.live()

	init(modelContainer: ModelContainer, appDelegate: AppDelegate) {
		self.fetch = Fetch(modelContainer: modelContainer)
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
		if let followedMembers = try? JSONEncoder().encode([1422: FollowPreferences()]) {
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
		.sheet(isPresented: $showMyMPSetup) {
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
							.frame(maxWidth: .infinity, alignment: .leading)
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.listRowBackground(router.selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
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
		let pathID = url.pathComponents.dropFirst().first.flatMap { Int($0) }
		switch host {
		case "member":
			if let id = pathID { navigateToMember(memberID: id) }
		case "vote":
			router.selectedTab = .accountability
		case "sitting", "event":
			// Rebuild as a path-based URL so ContentViewModel's sitting parser can consume it.
			let dateStr = url.pathComponents.dropFirst().first ?? ""
			if let rebuilt = URL(string: "cabinetdoor:///\(host)/\(dateStr)") {
				viewModel.onOpenURL(rebuilt, modelContext: modelContext, fetch: fetch)
			}
			router.selectedTab = .parliament
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
			}
			router.selectedTab = .search
		case "sitting":
			// /sitting/[date] → Parliament tab (date routing in ContentViewModel)
			viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
			router.selectedTab = .parliament
		case "speech":
			// Generic speech web share pages land on Parliament; specific speech
			// deep-links remain handled by ContentViewModel's legacy /app format.
			router.selectedTab = .parliament
		case "topic", "topics":
			// /topic/[topic-slug] and website /topics/[topic-slug].html → Search tab pre-filled
			if let slug = segments.dropFirst().first {
				router.pendingSearchQuery = searchQuery(fromWebSlug: slug)
				router.selectedTab = .search
			}
		case "riding", "ridings":
			// /riding/[riding-slug] and website /ridings/[riding-slug].html → Search tab pre-filled
			if let slug = segments.dropFirst().first {
				router.pendingSearchQuery = searchQuery(fromWebSlug: slug)
				router.selectedTab = .search
			}
		case "setup":
			// /setup/postal-code → postal code setup sheet on Home tab
			router.pendingShowPostalCodeSetup = true
			router.selectedTab = .home
		case "app", nil:
			if let (pathURL, originalPath) = encodedPathUniversalLink(from: url) {
				Task { await recordWebToAppOpen.execute(path: originalPath) }
				handleUniversalLink(pathURL)
				return
			}
			// Legacy query-parameter format: /app?date=...&subjectID=...
			viewModel.onOpenURL(url, modelContext: modelContext, fetch: fetch)
		default:
			// Home fallback for unrecognised paths — never crashes
			router.selectedTab = .home
		}
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
			// Navigate to Parliament tab — the sitting calendar shows today.
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
			SittingCalendarView(selectedDate: $viewModel.selectedDate)
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
		SittingLoaderView(
			date: date,
			selectedSubject: $viewModel.selectedSubject
		)
	}
}

// MARK: - App Store screenshot mode

private struct AppStoreScreenshotShowcaseView: View {
	@State private var selection = Self.initialSelection()

	private static func initialSelection() -> Int {
		let arguments = ProcessInfo.processInfo.arguments
		guard let index = arguments.firstIndex(of: "-AppStoreScreenshotPage"),
			  let valueIndex = arguments.index(index, offsetBy: 1, limitedBy: arguments.endIndex),
			  valueIndex < arguments.endIndex,
			  let page = Int(arguments[valueIndex]) else {
			return 0
		}

		return min(max(page, 0), 5)
	}

	private var pages: [AppStoreScreenshotPage] {
		[
			.init(
				headline: t("appStore.screenshot.page1.headline"),
				subtitle: t("appStore.screenshot.page1.subtitle"),
				accent: Color(red: 0.0, green: 0.44, blue: 0.89),
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
				accent: Color(red: 0.0, green: 0.64, blue: 0.69),
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
		TabView(selection: $selection) {
			ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
				AppStoreScreenshotPageView(page: page)
					.tag(index)
			}
		}
		.tabViewStyle(.page(indexDisplayMode: .never))
		.dynamicTypeSize(.large)
		.preferredColorScheme(.light)
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

	private func t(_ key: String) -> String {
		NSLocalizedString(key, comment: "")
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			LinearGradient(
				colors: [
					page.accent.opacity(0.28),
					Color(UIColor.systemBackground),
					Color(UIColor.secondarySystemBackground)
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
			.ignoresSafeArea()

			VStack(alignment: .leading, spacing: 20) {
				VStack(alignment: .leading, spacing: 10) {
					Text(page.headline)
						.font(.system(size: 31, weight: .heavy, design: .rounded))
						.foregroundStyle(.primary)
						.minimumScaleFactor(0.66)
						.lineLimit(3)
						.fixedSize(horizontal: false, vertical: true)
						.accessibilityIdentifier("appStoreScreenshotHeadline")

					Text(page.subtitle)
						.font(.system(size: 13, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.lineLimit(3)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.horizontal, 28)

				showcaseContent
					.padding(.horizontal, 20)

				Spacer(minLength: 18)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.padding(.top, 42)
		}
	}

	@ViewBuilder
	private var showcaseContent: some View {
		switch page.kind {
		case .overview:
			phoneFrame {
				VStack(alignment: .leading, spacing: 18) {
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
				VStack(alignment: .leading, spacing: 18) {
					header(t("appStore.screenshot.votes.header"), systemImage: "checklist.checked")
					Text("Gurbux Saini")
						.font(.system(size: 30, weight: .bold, design: .rounded))
					Text(t("appStore.screenshot.votes.memberDetail"))
						.font(.system(size: 18, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
					HStack(spacing: 14) {
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
				VStack(alignment: .leading, spacing: 18) {
					header(t("appStore.screenshot.myMP.header"), systemImage: "person.crop.circle.fill")
					HStack(spacing: 18) {
						Circle()
							.fill(Color.party(.liberal).opacity(0.18))
							.frame(width: 72, height: 72)
							.overlay(Text("GS").font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(Color.party(.liberal)))
						VStack(alignment: .leading, spacing: 6) {
							Text("Gurbux Saini")
								.font(.system(size: 23, weight: .bold, design: .rounded))
							Text("Fleetwood-Port Kells")
								.font(.system(size: 15, weight: .medium, design: .rounded))
								.foregroundStyle(.secondary)
							Text(t("appStore.screenshot.myMP.party"))
								.font(.system(size: 12, weight: .semibold, design: .rounded))
								.padding(.horizontal, 12)
								.padding(.vertical, 6)
								.background(Color.party(.liberal).opacity(0.16))
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
				VStack(alignment: .leading, spacing: 18) {
					header(t("appStore.screenshot.bill.header"), systemImage: "doc.text.fill")
					Text(t("appStore.screenshot.bill.title"))
						.font(.system(size: 21, weight: .bold, design: .rounded))
						.fixedSize(horizontal: false, vertical: true)
					VStack(alignment: .leading, spacing: 14) {
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
				VStack(alignment: .leading, spacing: 18) {
					header(t("appStore.screenshot.lobbying.header"), systemImage: "person.2.wave.2.fill")
					Text(t("appStore.screenshot.lobbying.title"))
						.font(.system(size: 21, weight: .bold, design: .rounded))
					activityRow(title: t("appStore.screenshot.lobbying.row1.title"), detail: t("appStore.screenshot.lobbying.row1.detail"), color: Color.party(.liberal))
					activityRow(title: t("appStore.screenshot.lobbying.row2.title"), detail: t("appStore.screenshot.lobbying.row2.detail"), color: page.accent)
					activityRow(title: t("appStore.screenshot.lobbying.row3.title"), detail: t("appStore.screenshot.lobbying.row3.detail"), color: .appWarning)
					sourceBadge(t("appStore.screenshot.lobbying.source"))
				}
			}
		case .contact:
			phoneFrame {
				VStack(alignment: .leading, spacing: 18) {
					header(t("appStore.screenshot.contact.header"), systemImage: "envelope.fill")
					VStack(alignment: .leading, spacing: 10) {
						Text(t("appStore.screenshot.contact.subject"))
							.font(.system(size: 16, weight: .semibold, design: .rounded))
							.foregroundStyle(.secondary)
						Text(t("appStore.screenshot.contact.subjectLine"))
							.font(.system(size: 19, weight: .bold, design: .rounded))
					}
					Divider()
					Text(t("appStore.screenshot.contact.body"))
						.font(.system(size: 17, weight: .regular, design: .rounded))
						.lineSpacing(5)
					Text(t("appStore.screenshot.contact.send"))
						.font(.system(size: 18, weight: .bold, design: .rounded))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 16)
						.background(page.accent)
						.foregroundStyle(.white)
						.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
				}
			}
		}
	}

	private func phoneFrame<Content: View>(@ViewBuilder content: () -> Content) -> AnyView {
		AnyView(
			VStack(alignment: .leading, spacing: 0) {
				content()
					.padding(18)
			}
			.frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
			.background(Color(UIColor.systemBackground))
			.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
			.shadow(color: .black.opacity(0.16), radius: 16, y: 10)
		)
	}

	private func header(_ title: String, systemImage: String) -> AnyView {
		AnyView(
			HStack(spacing: 12) {
				Image(systemName: systemImage)
					.font(.system(size: 18, weight: .bold))
					.foregroundStyle(page.accent)
				Text(title)
					.font(.system(size: 19, weight: .heavy, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(0.72)
				Spacer()
			}
		)
	}

	private func metricGrid(_ metrics: [(String, String, String)]) -> AnyView {
		AnyView(
			VStack(spacing: 10) {
				ForEach(metrics, id: \.0) { metric in
					HStack(spacing: 10) {
						Text(metric.0)
							.font(.system(size: 12, weight: .semibold, design: .rounded))
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.minimumScaleFactor(0.72)
							.frame(width: 82, alignment: .leading)
						Text(metric.1)
							.font(.system(size: 18, weight: .heavy, design: .rounded))
							.lineLimit(2)
							.minimumScaleFactor(0.7)
							.frame(width: 110, alignment: .leading)
						Text(metric.2)
							.font(.system(size: 12, weight: .medium, design: .rounded))
							.foregroundStyle(.secondary)
							.lineLimit(2)
							.minimumScaleFactor(0.75)
							.frame(maxWidth: .infinity, alignment: .leading)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
					.background(Color(UIColor.secondarySystemBackground))
					.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
			}
		)
	}

	private func activityRow(title: String, detail: String, color: Color) -> AnyView {
		AnyView(
			HStack(spacing: 14) {
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.fill(color)
					.frame(width: 7, height: 40)
				VStack(alignment: .leading, spacing: 5) {
					Text(title)
						.font(.system(size: 17, weight: .bold, design: .rounded))
						.lineLimit(2)
						.minimumScaleFactor(0.75)
					Text(detail)
						.font(.system(size: 13, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.minimumScaleFactor(0.75)
				}
				Spacer()
			}
			.padding(12)
			.background(Color(UIColor.secondarySystemBackground))
			.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		)
	}

	private func votePill(_ label: String, count: String, color: Color) -> AnyView {
		AnyView(
			VStack(spacing: 6) {
				Text(count)
					.font(.system(size: 22, weight: .heavy, design: .rounded))
				Text(label)
					.font(.system(size: 12, weight: .bold, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(0.72)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 16)
			.background(color.opacity(0.14))
			.foregroundStyle(color)
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		)
	}

	private func stage(_ label: String, done: Bool, current: Bool = false) -> AnyView {
		AnyView(
			HStack(spacing: 12) {
				Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
					.foregroundStyle(done ? .appPositive : current ? page.accent : .secondary)
				Text(label)
					.font(.system(size: 17, weight: current ? .heavy : .semibold, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(0.75)
				Spacer()
				if current {
					Text(t("appStore.screenshot.bill.current"))
						.font(.system(size: 14, weight: .bold, design: .rounded))
						.padding(.horizontal, 10)
						.padding(.vertical, 5)
						.background(page.accent.opacity(0.14))
						.foregroundStyle(page.accent)
						.clipShape(Capsule())
				}
			}
		)
	}

	private func sourceBadge(_ text: String) -> AnyView {
		AnyView(
			Text(text)
				.font(.system(size: 11, weight: .semibold, design: .rounded))
				.foregroundStyle(.secondary)
				.lineLimit(2)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(Color(UIColor.tertiarySystemBackground))
				.clipShape(Capsule())
		)
	}
}
