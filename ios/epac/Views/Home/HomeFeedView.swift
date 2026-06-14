//
//  HomeFeedView.swift
//  epac
//
//  Personalized Home feed (EPAC-50).
//  Replaces the raw MyMPView in the Home tab with 5 graceful sections:
//  1. Past debates entry point
//  2. Your MP's activity (postal-code-based, or setup prompt)
//  3. Followed bills (up to 3 + see-all link)
//  4. Followed topics (chip row + manage link)
//  5. Most recent debates (from latest Hansard in SwiftData)
//

import ActivityView
import SwiftData
import SwiftUI

private enum HomeFeedLayout {
    static let refreshToastAnimationDuration = EpacAnimation.standard
    static let refreshToastDurationSeconds: Int64 = 3
    static let iconColumnWidth = EpacIconSize.m
    static let followedBillsLimit = 3
    static let compactVerticalPadding = EpacSpacing.xxs
    static let followedTopicsLimit = 6
    static let senatorsLimit = 3
    static let healthcarePreviewLimit = 2
    static let reorderBillsThreshold = 5
    static let unreadDotSize: CGFloat = 8
    static let sponsorLineLimit = 2
}

@MainActor
struct HomeFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fetch: Fetch
    @Environment(NavigationRouter.self) private var router
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var latestVote: HomeVoteRecord?
    @State private var latestMemberVote: HomeMemberVoteRecord?
    @State private var latestSpeechHighlight: HomeSpeechHighlight?
    @State private var myMPActivityCount = 0
    @State private var showPostalCodeSetup = false
    @State private var showSettings = false
    @State private var recentSubjectTitles: [String] = []
    @State private var latestHansardDate: Date?
    @State private var billStore = BillFollowStore.shared
    @State private var topicStore = TopicFollowStore.shared
    @State private var postalCodeStore = PostalCodeStore.shared
    @State private var provinceAbbrev: String = ""
    @State private var mySenators: [Senator] = []
    @State private var showRefreshToast = false
    @State private var followedBills: [FollowedBill] = []
    @State private var showNotifySettingsAlert = false
    @State private var selectedBillForNotify: FollowedBill?
    @State private var shareItem: ActivityItem?
    @State private var recentLawBills: [Bill] = []

    var body: some View {
        NavigationStack {
            List {
                todaySection
                electionCountdownSection
                myMPSection
                if !recentLawBills.isEmpty {
                    recentlyBecameLawSection
                }
                followingSection
                if !mySenators.isEmpty {
                    senatorsSection
                }
                reconciliationContextCard
                correctionsContextCard
                healthcareContextCard
                consumerPriceIndexContextCard
                studentFinanceContextCard
                employmentInsuranceContextCard
                transportationSafetyContextCard
                if !recentSubjectTitles.isEmpty {
                    recentDebatesSection
                }
                if postalCodeStore.savedMemberName == nil
                    && billStore.followedNumbers.isEmpty
                    && topicStore.followedIDs.isEmpty {
                    Section {
                        EmptyStateView(
                            icon: "person.wave.2",
                            title: NSLocalizedString("empty.home.title", comment: ""),
                            message: NSLocalizedString("empty.home.message", comment: ""),
                            action: EmptyStateAction(
                                label: NSLocalizedString("empty.home.action", comment: ""),
                                handler: { showPostalCodeSetup = true }
                            )
                        )
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .adaptiveReadingWidth()
            .accessibilityIdentifier("home-feed-scroll")
            .refreshable {
                await loadFeed()
                if !networkMonitor.isConnected {
                    showRefreshToast = true
                }
            }
            .overlay(alignment: .top) {
                if showRefreshToast {
                    HomeRefreshErrorToast()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: HomeFeedLayout.refreshToastAnimationDuration), value: showRefreshToast)
            .task(id: showRefreshToast) {
                guard showRefreshToast else { return }
                try? await Task.sleep(for: .seconds(HomeFeedLayout.refreshToastDurationSeconds))
                showRefreshToast = false
            }
            .navigationTitle(NSLocalizedString("Home", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label(NSLocalizedString("settings.title", comment: ""), systemImage: "gearshape")
                    }
                    .accessibilityLabel(NSLocalizedString("settings.title", comment: ""))
                }
            }
            .task {
                await loadFeed()
            }
            .regularSizeClassFormSheet(isPresented: $showPostalCodeSetup) {
                PostalCodeSetupView { showPostalCodeSetup = false }
            }
            .onChange(of: postalCodeStore.savedMemberName) {
                Task { await loadFeed() }
            }
            .regularSizeClassFormSheet(isPresented: $showSettings) {
                SettingsView()
            }
            .perfSignpostInterval(.homeFeedView)
            .activitySheet($shareItem)
            .alert(
                NSLocalizedString("bill.contextMenu.notifySettings", comment: ""),
                isPresented: $showNotifySettingsAlert,
                presenting: selectedBillForNotify
            ) { _ in
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: { bill in
                Text(String(format: NSLocalizedString("Notification settings for Bill %@ will be added in a future update.", comment: ""), bill.number))
            }
        }
    }

    // MARK: - Section 1: Past debates

    private var todaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: EpacSpacing.m) {
                todayHeader

                Divider()

                if let vote = latestVote {
                    todayVoteRow(vote)
                }

                if let highlight = latestSpeechHighlight {
                    NavigationLink {
                        if let hansard = fetchHansard(by: highlight.hansardID),
                           let subject = hansard.orders.flatMap(\.subjects).first(where: { $0.title == highlight.subjectTitle })
                            ?? hansard.orders.first?.subjects.first {
                            SpeechView(hansard: hansard, subject: subject)
                        }
                    } label: {
                        todayMetricRow(
                            icon: "quote.bubble.fill",
                            title: NSLocalizedString("home.today.latestSpeech", comment: ""),
                            headline: highlight.excerpt,
                            detail: "\(highlight.memberName) · \(highlight.hansardDate.formatted(date: .abbreviated, time: .omitted))"
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded { trackTodayCardTap("speech") })
                } else if hasPersonalizedContext {
                    todayMetricRow(
                        icon: "quote.bubble",
                        title: NSLocalizedString("home.today.latestSpeech", comment: ""),
                        headline: NSLocalizedString("home.today.noSpeech", comment: ""),
                        detail: NSLocalizedString("home.today.cachedOnly", comment: "")
                    )
                }

                Button {
                    trackTodayCardTap("more")
                    router.selectedTab = .parliament
                } label: {
                    Label(NSLocalizedString("home.today.more", comment: ""), systemImage: "calendar")
                        .font(.epacCaption.weight(.semibold))
                        .foregroundStyle(Color.epacBrand.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, EpacSpacing.s)
            .accessibilityLabel(NSLocalizedString("home.debates.title", comment: ""))
            .accessibilityHint("Opens Parliament tab")
            .accessibilityIdentifier("home-feed-today-card")
        }
    }

    private var todayHeader: some View {
        Button {
            trackTodayCardTap("status")
            router.selectedTab = .parliament
        } label: {
            HStack(alignment: .top, spacing: EpacSpacing.s) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(Color.epacBrand.accent)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                    Text(NSLocalizedString("home.debates.title", comment: ""))
                        .font(.epacHeadline)
                        .foregroundStyle(Color.epacBrand.accent)
                    Text(NSLocalizedString("home.debates.subtitle", comment: ""))
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacText.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func todayVoteRow(_ vote: HomeVoteRecord) -> some View {
        if let mv = latestMemberVote {
            NavigationLink {
                if let rv = fetchRecordedVote(by: vote.voteID),
                   let memberVote = fetchMemberVote(memberID: mv.memberID, voteID: mv.voteID) {
                    VoteDetailView(mv: memberVote, rv: rv)
                }
            } label: {
                todayMetricRow(
                    icon: "checkmark.ballot.fill",
                    title: NSLocalizedString("home.today.latestVote", comment: ""),
                    headline: vote.descriptionEn.isEmpty ? "Vote #\(vote.number)" : vote.descriptionEn,
                    detail: voteSummary(vote, memberVote: mv)
                )
            }
            .simultaneousGesture(TapGesture().onEnded { trackTodayCardTap("vote") })
        } else {
            Button {
                trackTodayCardTap("voteSearch")
                if !vote.billNumberCode.isEmpty {
                    router.pendingSearchQuery = vote.billNumberCode
                    router.selectedTab = .search
                } else {
                    router.selectedTab = .accountability
                }
            } label: {
                todayMetricRow(
                    icon: "checkmark.ballot.fill",
                    title: NSLocalizedString("home.today.latestVote", comment: ""),
                    headline: vote.descriptionEn.isEmpty ? "Vote #\(vote.number)" : vote.descriptionEn,
                    detail: voteSummary(vote, memberVote: nil)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func todayMetricRow(
        icon: String,
        title: String,
        headline: String,
        detail: String,
        detailLineLimit: Int? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: EpacSpacing.s) {
            Image(systemName: icon)
                .foregroundStyle(Color.epacBrand.accent)
                .frame(width: HomeFeedLayout.iconColumnWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                Text(title)
                    .font(.epacCaption.weight(.semibold))
                    .foregroundStyle(Color.epacText.secondary)
                Text(headline)
                    .font(.epacSubheadline.weight(.semibold))
                    .foregroundStyle(Color.epacText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
                    .lineLimit(detailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Section 2: Your MP's activity

    private var myMPSection: some View {
        Section {
            if let name = postalCodeStore.savedMemberName {
                NavigationLink(destination: MyMPView()) {
                    HStack {
                        Image(systemName: "person.fill.viewfinder")
                            .foregroundStyle(Color.epacBrand.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                            Text(name)
                                .font(.epacSubheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(String(format: NSLocalizedString("home.myMP.activityCount", comment: ""), myMPActivityCount))
                                .font(.epacCaption)
                                .foregroundStyle(Color.epacText.secondary)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("home-feed-my-mp-link")
            } else {
                Button {
                    showPostalCodeSetup = true
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color.epacStatus.warning)
                            .accessibilityHidden(true)
                        Text(NSLocalizedString("home.myMP.notSet", comment: ""))
                            .font(.epacSubheadline)
                        Spacer()
                        Text(NSLocalizedString("riding.setup.lookupButton", comment: ""))
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacBrand.accent)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("home-feed-my-mp-link")
            }
        }
    }

    // MARK: - Section 3: Following

    private var recentlyBecameLawSection: some View {
        Section(header: Text(NSLocalizedString("home.recentlyBecameLaw", comment: "")).accessibilityAddTraits(.isHeader)) {
            RecentlyBecameLawCard(
                bills: recentLawBills,
                sponsorMember: sponsorMember(for:)
            )
            NavigationLink(destination: BillsView(initialTab: .becameLaw)) {
                Text(NSLocalizedString("home.seeLaws", comment: ""))
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacBrand.accent)
            }
        }
    }

    private var followingSection: some View {
        Section(header: Text(NSLocalizedString("home.following", comment: "")).accessibilityAddTraits(.isHeader)) {
            billsGroup
            if !topicStore.followedIDs.isEmpty {
                topicsGroup
            }
        }
    }

    @ViewBuilder
    private var billsGroup: some View {
        HStack {
            Text(NSLocalizedString("home.following.bills", comment: ""))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if followedBills.count > HomeFeedLayout.reorderBillsThreshold {
                EditButton()
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.epacBrand.accent)
            }
        }
        .listRowSeparator(.hidden)

        if followedBills.isEmpty {
            VStack(alignment: .leading, spacing: EpacSpacing.s) {
                Text(NSLocalizedString("home.following.bills.empty.message", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Color.epacText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    router.selectedTab = .search
                } label: {
                    Text(NSLocalizedString("home.following.bills.empty.cta", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.epacBrand.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, EpacSpacing.xs)
        } else {
            ForEach(followedBills) { followed in
                let billToUse = followed.bill ?? fallbackBill(for: followed)
                NavigationLink(destination: BillDetailView(bill: billToUse)) {
                    HStack(alignment: .center, spacing: EpacSpacing.s) {
                        if followed.hasUnreadUpdate {
                            Circle()
                                .fill(Color.epacBrand.accent)
                                .frame(width: HomeFeedLayout.unreadDotSize, height: HomeFeedLayout.unreadDotSize)
                                .accessibilityLabel("Unread update")
                        }
                        VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                            HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.xs) {
                                Text(followed.number)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.epacText.primary)
                                Text(followed.title)
                                    .font(.caption)
                                    .foregroundStyle(Color.epacText.secondary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: EpacSpacing.s) {
                                BillStatusBadge(status: followed.status)
                                Text(followed.lastUpdateTimestamp.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(Color.epacText.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, HomeFeedLayout.compactVerticalPadding)
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        billStore.unfollow(followed.number)
                        Task { await loadFeed() }
                    } label: {
                        Label(NSLocalizedString("bill.unfollow", comment: ""), systemImage: "trash")
                    }
                }
                .contextMenu {
                    contextMenu(for: followed)
                }
            }
            .onMove(perform: followedBills.count > HomeFeedLayout.reorderBillsThreshold ? { source, destination in
                billStore.moveFollowedBills(from: source, to: destination)
                Task { await loadFeed() }
            } : nil)
        }
    }

    @ViewBuilder
    private var topicsGroup: some View {
        HStack {
            Text(NSLocalizedString("home.following.topics", comment: ""))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .listRowSeparator(.hidden)
        .padding(.top, EpacSpacing.s)

        let followedTopics = ParliamentaryTopic.all.filter { topicStore.isFollowing($0.id) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: EpacSpacing.s) {
                ForEach(followedTopics.prefix(HomeFeedLayout.followedTopicsLimit)) { topic in
                    Text(topic.localizedName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.epacText.onAccent)
                        .padding(.horizontal, EpacSpacing.s)
                        .padding(.vertical, EpacSpacing.xs)
                        .background(Color.epacBrand.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, EpacSpacing.xs)
        }
        NavigationLink(destination: TopicsView()) {
            Text(NSLocalizedString("home.manageTopics", comment: ""))
                .font(.caption)
                .foregroundStyle(Color.epacBrand.accent)
        }
    }

    private func fallbackBill(for followed: FollowedBill) -> Bill {
        Bill(
            id: followed.number,
            number: followed.number,
            title: followed.title,
            sponsorName: "",
            status: followed.status,
            currentStage: followed.currentStage,
            introducedDate: followed.lastUpdateTimestamp,
            royalAssentDate: nil,
            summary: nil,
            sponsorProfileURL: nil,
            stages: [],
            legisInfoURL: URL(string: "https://www.parl.ca")!,
            type: .unknown,
            parliament: 0,
            session: 0
        )
    }

    @ViewBuilder
    private func contextMenu(for followed: FollowedBill) -> some View {
        Button(role: .destructive) {
            billStore.unfollow(followed.number)
            Task { await loadFeed() }
        } label: {
            Label(NSLocalizedString("bill.unfollow", comment: ""), systemImage: "doc.badge.clock")
        }

        let billToUse = followed.bill ?? fallbackBill(for: followed)
        Button {
            shareItem = BillSharer.activityItem(for: billToUse)
        } label: {
            Label(NSLocalizedString("bill.share", comment: ""), systemImage: "square.and.arrow.up")
        }

        Button {
            selectedBillForNotify = followed
            showNotifySettingsAlert = true
        } label: {
            Label(NSLocalizedString("bill.contextMenu.notifySettings", comment: ""), systemImage: "bell")
        }
    }

    // MARK: - Section 4b: My Senators (shown when province is known)

    private var senatorsSection: some View {
        Section(header: Text(NSLocalizedString("senate.mySenators.title", comment: "")).accessibilityAddTraits(.isHeader)) {
            ForEach(mySenators.prefix(HomeFeedLayout.senatorsLimit)) { senator in
                SenatorCard(senator: senator)
            }
        }
    }

    // MARK: - Reconciliation contextual card (shown when Indigenous/reconciliation topic is followed)

    @ViewBuilder
    private var reconciliationContextCard: some View {
        if topicStore.isFollowing("indigenous") {
            Section {
                ReconciliationContextCard()
            } header: {
                Text("Reconciliation")
            }
        }
    }

    // MARK: - Corrections contextual card (shown when Indigenous or justice topic is followed)

    @ViewBuilder
    private var correctionsContextCard: some View {
        if topicStore.isFollowing("justice") || topicStore.isFollowing("indigenous"),
           let snapshot = CorrectionsStatisticsDatabase.snapshot(),
           let latest = snapshot.latestAnnualStatistic {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    Text("Federal corrections")
                        .font(.epacSubheadline.weight(.semibold))
                    HStack {
                        Text("Indigenous in custody")
                            .font(.epacCallout)
                        Spacer()
                        Text(percentLabel(latest.indigenousInCustodyPercent))
                            .font(.epacCallout.monospacedDigit())
                    }
                    HStack {
                        Text("Canada population share")
                            .font(.epacCallout)
                        Spacer()
                        Text(percentLabel(snapshot.indigenousPopulationShare.percentOfCanada))
                            .font(.epacCallout.monospacedDigit())
                    }
                    HStack {
                        Text("5-year recidivism rate")
                            .font(.epacCallout)
                        Spacer()
                        Text(percentLabel(latest.recidivismRatePercent))
                            .font(.epacCallout.monospacedDigit())
                    }
                    Link("View source", destination: snapshot.source.url)
                        .font(.epacCaption)
                }
            } header: {
                Text("Federal Corrections")
            } footer: {
                Text("Reference year: \(CorrectionsStatisticsDatabase.fiscalYearLabel(snapshot.referenceFiscalYear))")
            }
        }
    }

    // MARK: - Healthcare contextual card (shown when "healthcare" topic followed + province known)

    @ViewBuilder
    private var healthcareContextCard: some View {
        if topicStore.isFollowing("healthcare") && !provinceAbbrev.isEmpty {
            let healthData = CIHIWaitTimeDatabase.waitTimes(for: provinceAbbrev)
            if !healthData.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: EpacSpacing.s) {
                        Text(String(format: NSLocalizedString("cihi.contextCard.title", comment: ""), provinceAbbrev))
                            .font(.epacSubheadline.weight(.semibold))
                        ForEach(healthData.prefix(HomeFeedLayout.healthcarePreviewLimit), id: \.procedure) { wt in
                            HStack {
                                Text(wt.procedure).font(.epacCallout)
                                Spacer()
                                Text("\(Int(wt.medianWeeks))w median").font(.epacCallout.monospacedDigit())
                            }
                        }
                        Link(NSLocalizedString("cihi.viewSource", comment: ""), destination: CIHIWaitTimeDatabase.sourceURL)
                            .font(.epacCaption)
                    }
                } header: {
                    Text(NSLocalizedString("cihi.sectionTitle.short", comment: ""))
                }
            }
        }
    }

    // MARK: - Consumer Price Index contextual card (shown when "economy" or "agriculture" topic followed + province known)

    @ViewBuilder
    private var consumerPriceIndexContextCard: some View {
        if topicStore.isFollowing("economy") || topicStore.isFollowing("agriculture"),
           let cpi = ConsumerPriceIndexStatisticsDatabase.statistic(for: provinceAbbrev) {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    Text("Inflation in \(provinceAbbrev)")
                        .font(.epacSubheadline.weight(.semibold))
                    HStack {
                        Text("All-items")
                            .font(.epacCallout)
                        Spacer()
                        Text(yearOverYearLabel(cpi.allItemsYearOverYearPercent))
                            .font(.epacCallout.monospacedDigit())
                    }
                    HStack {
                        Text("Food")
                            .font(.epacCallout)
                        Spacer()
                        Text(yearOverYearLabel(cpi.foodYearOverYearPercent))
                            .font(.epacCallout.monospacedDigit())
                    }
                    HStack {
                        Text("Canada")
                            .font(.epacCallout)
                        Spacer()
                        Text(yearOverYearLabel(cpi.nationalAllItemsYearOverYearPercent))
                            .font(.epacCallout.monospacedDigit())
                    }
                    Link("View source", destination: ConsumerPriceIndexStatisticsDatabase.snapshot()?.source.url
                        ?? ConsumerPriceIndexStatisticsDatabase.fallbackSource.url)
                        .font(.epacCaption)
                }
            } header: {
                Text("Consumer Price Index")
            } footer: {
                Text("Reference month: \(ConsumerPriceIndexStatisticsDatabase.monthLabel(cpi.referenceMonth))")
            }
        }
    }

    // MARK: - Student finance contextual card (shown when "education" topic followed + province known)

    @ViewBuilder
    private var studentFinanceContextCard: some View {
        if topicStore.isFollowing("education"),
           let finance = StudentFinancialAssistanceStatisticsDatabase.statistic(for: provinceAbbrev),
           let tuition = finance.latestTuitionYear {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    Text("Student costs in \(provinceAbbrev)")
                        .font(.epacSubheadline.weight(.semibold))
                    HStack {
                        Text("Average undergraduate tuition")
                            .font(.epacCallout)
                        Spacer()
                        Text(tuition.averageUndergraduateTuition.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
                            .font(.epacCallout.monospacedDigit())
                    }
                    if let tuitionChange = tuition.yearOverYearChangePercent {
                        HStack {
                            Text("Tuition vs. last year")
                                .font(.epacCallout)
                            Spacer()
                            Text(yearOverYearLabel(tuitionChange))
                                .font(.epacCallout.monospacedDigit())
                        }
                    }
                    if let latestCSFA = finance.latestCSFAYear {
                        HStack {
                            Text("CSL recipients")
                                .font(.epacCallout)
                            Spacer()
                            Text(latestCSFA.loanRecipients.formatted())
                                .font(.epacCallout.monospacedDigit())
                        }
                    }
                    Link("View source", destination: StudentFinancialAssistanceStatisticsDatabase.snapshot()?.source.url
                        ?? StudentFinancialAssistanceStatisticsDatabase.fallbackSource.url)
                        .font(.epacCaption)
                }
            } header: {
                Text("Student Financial Assistance")
            } footer: {
                Text("Tuition year: \(StudentFinancialAssistanceStatisticsDatabase.academicYearLabel(tuition.academicYear))")
            }
        }
    }

    // MARK: - Employment Insurance contextual card (shown when "labour" topic followed + province known)

    @ViewBuilder
    private var employmentInsuranceContextCard: some View {
        if topicStore.isFollowing("labour"),
           let ei = EmploymentInsuranceStatisticsDatabase.statistic(for: provinceAbbrev) {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    Text("EI in \(provinceAbbrev)")
                        .font(.epacSubheadline.weight(.semibold))
                    HStack {
                        Text("Regular beneficiaries")
                            .font(.epacCallout)
                        Spacer()
                        Text(ei.beneficiaries.formatted())
                            .font(.epacCallout.monospacedDigit())
                    }
                    HStack {
                        Text("Average weekly benefit")
                            .font(.epacCallout)
                        Spacer()
                        Text(ei.averageWeeklyBenefit.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
                            .font(.epacCallout.monospacedDigit())
                    }
                    Link("View source", destination: EmploymentInsuranceStatisticsDatabase.snapshot()?.source.url
                        ?? EmploymentInsuranceStatisticsDatabase.fallbackSource.url)
                        .font(.epacCaption)
                }
            } header: {
                Text("Employment Insurance")
            } footer: {
                Text("Reference month: \(EmploymentInsuranceStatisticsDatabase.monthLabel(ei.referenceMonth))")
            }
        }
    }

    // MARK: - Transportation safety contextual card (shown when "transport" topic followed + province known)

    @ViewBuilder
    private var transportationSafetyContextCard: some View {
        if topicStore.isFollowing("transport"),
           let road = TransportSafetyStatisticsDatabase.roadStatistic(for: provinceAbbrev),
           let rail = TransportSafetyStatisticsDatabase.latestModeYear("rail") {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    Text("Road safety in \(provinceAbbrev)")
                        .font(.epacSubheadline.weight(.semibold))
                    HStack {
                        Text("Fatalities")
                            .font(.epacCallout)
                        Spacer()
                        Text(TransportSafetyStatisticsDatabase.rateLabel(road.fatalitiesPer100k, unit: "per 100k"))
                            .font(.epacCallout.monospacedDigit())
                    }
                    HStack {
                        Text("Rail accidents \(rail.year)")
                            .font(.epacCallout)
                        Spacer()
                        Text(rail.accidents.formatted())
                            .font(.epacCallout.monospacedDigit())
                    }
                    NavigationLink(destination: TransportationSafetyView()) {
                        Text("View national transport safety")
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacBrand.accent)
                    }
                }
            } header: {
                Text("Transport Safety")
            } footer: {
                Text("Road reference year: \(road.referenceYear)")
            }
        }
    }

    // MARK: - Election countdown

    // The mandated date is statutorily fixed and cheap to compute, so the
    // values are recalculated on each render rather than cached in @State.
    private var electionCountdownSection: some View {
        let lastElection = ElectionDateCalculator.last45thGeneralElection
        let mandated = ElectionDateCalculator.nextMandatedDate(after: lastElection)
        let days = ElectionDateCalculator.daysRemaining(now: Date(), mandatedDate: mandated)
        return Section {
            NavigationLink(destination: ElectionDetailView(
                lastElectionDate: lastElection,
                mandatedDate: mandated,
                daysRemaining: days
            )) {
                ElectionCountdownCard(mandatedDate: mandated, daysRemaining: days)
            }
        }
    }

    // MARK: - Section 5: Recent debates

    private var recentDebatesSection: some View {
        Section(header: Text(NSLocalizedString("home.recentDebates", comment: "")).accessibilityAddTraits(.isHeader)) {
            ForEach(recentSubjectTitles, id: \.self) { title in
                Text(title)
                    .font(.epacSubheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, EpacSpacing.xs)
            }
            if latestHansardDate != nil {
                Button {
                    router.selectedTab = .parliament
                } label: {
                    Text(NSLocalizedString("home.seeAllDebates", comment: ""))
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacBrand.accent)
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadFeed() async {
        let span = Telemetry.startSpan(
            name: PerformanceSignpostContract.SpanName.launchHomeFeed,
            operation: "launch.home-feed"
        )
        defer { span.finish() }

        let useCase = LoadHomeFeed(
            repository: HomeFeedSwiftDataRepository(modelContext: modelContext),
            followPreferenceReading: FollowPreferenceAdapter()
        )
        let snapshot = await useCase.execute()

        self.latestVote = snapshot.latestVote
        self.latestMemberVote = snapshot.latestMemberVote
        self.latestSpeechHighlight = snapshot.latestSpeechHighlight
        self.myMPActivityCount = snapshot.myMPActivityCount
        self.recentSubjectTitles = snapshot.recentSubjectTitles
        self.latestHansardDate = snapshot.latestHansardDate

        self.provinceAbbrev = snapshot.civicContext.provinceAbbrev
        self.mySenators = snapshot.civicContext.mySenators

        let loadFollowed = LoadFollowedBills(
            followedBillReadPort: FollowPreferenceAdapter(),
            billStatusReadPort: LEGISinfoBillRepository()
        )
        if let result = try? await loadFollowed.execute() {
            self.followedBills = result
        }

        self.recentLawBills = (try? await TrackRoyalAssent(repository: LEGISinfoBillRepository()).recentlyBecameLaw()) ?? []
    }

    private func sponsorMember(for bill: Bill) -> ParliamentMember? {
        let sponsor = normalizedSponsorName(bill.sponsorName)
        guard !sponsor.isEmpty,
              let members = try? modelContext.fetch(FetchDescriptor<ParliamentMember>()) else {
            return nil
        }

        return members.first { member in
            let fullName = normalizedSponsorName(member.name)
            return fullName == sponsor
                || sponsor.contains(normalizedSponsorName(member.lastName))
                    && sponsor.contains(normalizedSponsorName(member.firstName))
        }
    }

    private func normalizedSponsorName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "Hon. ", with: "")
            .replacingOccurrences(of: "The Honourable ", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPersonalizedContext: Bool {
        postalCodeStore.savedMemberName != nil || !MemberFollowStore.shared.followedIDs.isEmpty
    }

    private func voteSummary(_ vote: HomeVoteRecord, memberVote: HomeMemberVoteRecord?) -> String {
        var parts: [String] = []
        if !vote.billNumberCode.isEmpty { parts.append(vote.billNumberCode) }
        if !vote.resultEn.isEmpty { parts.append(vote.resultEn) }
        parts.append("\(NSLocalizedString("votes.yea", comment: "")) \(vote.yea) · \(NSLocalizedString("votes.nay", comment: "")) \(vote.nay)")
        if let memberVote {
            parts.append(String(format: NSLocalizedString("home.today.myMPBallot", comment: ""), memberVote.recordedVote))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - SwiftData navigation helpers (lazy lookup for domain-typed decisions)

    private func fetchHansard(by hansardID: String) -> Hansard? {
        let descriptor = FetchDescriptor<Hansard>(predicate: #Predicate { $0.hansardID == hansardID })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchRecordedVote(by voteID: Int) -> RecordedVote? {
        var descriptor = FetchDescriptor<RecordedVote>(predicate: #Predicate { $0.voteID == voteID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchMemberVote(memberID: Int, voteID: Int) -> MemberVote? {
        var descriptor = FetchDescriptor<MemberVote>(
            predicate: #Predicate<MemberVote> { $0.memberID == memberID && $0.voteID == voteID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func yearOverYearLabel(_ value: Double) -> String {
        if value > 0 {
            return "+\(value.formatted(.number.precision(.fractionLength(1))))%"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func percentLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func trackTodayCardTap(_ target: String) {
        Log.info("home.today.tap target=\(target)")
    }
}

struct RecentlyBecameLawCard: View {
    let bills: [Bill]
    let sponsorMember: @MainActor (Bill) -> ParliamentMember?

    init(
        bills: [Bill],
        sponsorMember: @escaping @MainActor (Bill) -> ParliamentMember? = { _ in nil }
    ) {
        self.bills = bills
        self.sponsorMember = sponsorMember
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.m) {
            ForEach(bills) { bill in
                lawRow(for: bill)
                if bill.id != bills.last?.id {
                    Divider()
                }
            }
        }
        .padding(.vertical, EpacSpacing.xs)
        .accessibilityIdentifier("home-recently-became-law-card")
    }

    private func lawRow(for bill: Bill) -> some View {
        VStack(alignment: .leading, spacing: EpacSpacing.s) {
            NavigationLink(destination: BillDetailView(bill: bill)) {
                VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.xs) {
                        Text(bill.number)
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(Color.epacBrand.accent)
                        Text(royalAssentDateLabel(for: bill))
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacText.secondary)
                    }
                    Text(bill.title)
                        .font(.epacSubheadline.weight(.semibold))
                        .foregroundStyle(Color.epacText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let summary = bill.summary, !summary.isEmpty {
                Text(summary)
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: EpacSpacing.s) {
                    sponsorLabel(for: bill)
                    Spacer()
                    legisInfoLink(for: bill)
                }
                VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                    sponsorLabel(for: bill)
                    legisInfoLink(for: bill)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: bill))
    }

    private func sponsorLabel(for bill: Bill) -> some View {
        Group {
            if let member = sponsorMember(bill) {
                NavigationLink(destination: MemberProfileView(member: member)) {
                    Label(member.name, systemImage: "person.crop.circle")
                }
            } else if let profileURL = bill.sponsorProfileURL {
                Link(destination: profileURL) {
                    Label(bill.sponsorName, systemImage: "person.crop.circle")
                }
            } else if !bill.sponsorName.isEmpty {
                Label(bill.sponsorName, systemImage: "person.crop.circle")
            }
        }
        .font(.epacCaption)
        .foregroundStyle(Color.epacText.secondary)
        .lineLimit(HomeFeedLayout.sponsorLineLimit)
    }

    private func legisInfoLink(for bill: Bill) -> some View {
        Link(destination: bill.legisInfoURL) {
            Label(NSLocalizedString("bills.detail.legisinfo", comment: ""), systemImage: "arrow.up.right.square")
        }
        .font(.epacCaption)
        .foregroundStyle(Color.epacBrand.accent)
    }

    private func royalAssentDateLabel(for bill: Bill) -> String {
        guard let date = bill.becameLawDate else {
            return NSLocalizedString("bill.status.royalAssent", comment: "")
        }
        return String(
            format: NSLocalizedString("home.recentlyBecameLaw.date", comment: ""),
            date.formatted(date: .abbreviated, time: .omitted)
        )
    }

    private func accessibilityLabel(for bill: Bill) -> String {
        [
            bill.number,
            bill.title,
            royalAssentDateLabel(for: bill),
            bill.sponsorName
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}
