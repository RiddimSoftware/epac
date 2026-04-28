//
//  HomeFeedView.swift
//  epac
//
//  Personalized Home feed (EPAC-50).
//  Replaces the raw MyMPView in the Home tab with 5 graceful sections:
//  1. Today in Parliament (sitting day check)
//  2. Your MP's activity (postal-code-based, or setup prompt)
//  3. Followed bills (up to 3 + see-all link)
//  4. Followed topics (chip row + manage link)
//  5. Today's most recent debates (from latest Hansard in SwiftData)
//

import SwiftData
import SwiftUI

@MainActor
struct HomeFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSittingToday = false
    @State private var parliamentDayStatus: HomeParliamentDayStatus = .notSitting
    @State private var liveParliamentStatus: LiveParliamentStatus?
    @State private var nextSittingDate: Date?
    @State private var latestRecordedVote: RecordedVote?
    @State private var latestMemberVote: MemberVote?
    @State private var latestSpeechHighlight: HomeSpeechHighlight?
    @State private var myMPActivityCount = 0
    @State private var showPostalCodeSetup = false
    @State private var showSettings = false
    @State private var recentSubjects: [SubjectOfBusiness] = []
    @State private var latestHansard: Hansard?
    @State private var billStore = BillFollowStore.shared
    @State private var topicStore = TopicFollowStore.shared
    @State private var provinceAbbrev: String = ""
    @State private var mySenators: [Senator] = []
    @State private var showRefreshToast = false
    @State private var showLiveInfo = false
    @State private var postSittingHansard: Hansard?

    private let liveParliamentService = LiveParliamentService()

    var body: some View {
        NavigationStack {
            List {
                switch liveCardState {
                case .live(let status):
                    liveParliamentSection(status)
                case .todayPublished(let hansard, let subject):
                    postSittingSection(hansard: hansard, subject: subject)
                case .todayPending:
                    postSittingPendingSection
                case .hidden:
                    EmptyView()
                }
                // Always show today's Parliament status — VoiceOver users need to know whether sitting.
                todaySection
                electionCountdownSection
                myMPSection
                if !billStore.followedNumbers.isEmpty {
                    followedBillsSection
                }
                if !topicStore.followedIDs.isEmpty {
                    followedTopicsSection
                }
                if !mySenators.isEmpty {
                    senatorsSection
                }
                reconciliationContextCard
                healthcareContextCard
                consumerPriceIndexContextCard
                studentFinanceContextCard
                employmentInsuranceContextCard
                if !recentSubjects.isEmpty {
                    recentDebatesSection
                }
                if PostalCodeViewModel.savedMemberName == nil
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
            .accessibilityIdentifier("home-feed-scroll")
            .refreshable {
                await loadFeed()
                await refreshLiveParliamentStatus()
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
            .animation(.easeInOut(duration: 0.3), value: showRefreshToast)
            .task(id: showRefreshToast) {
                guard showRefreshToast else { return }
                try? await Task.sleep(for: .seconds(3))
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
                await refreshLiveParliamentStatus()
            }
            .task(id: scenePhase) {
                await pollLiveParliamentStatus(while: scenePhase)
            }
            .sheet(isPresented: $showPostalCodeSetup) {
                PostalCodeSetupView { showPostalCodeSetup = false }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Section 1: Today in Parliament

    private func liveParliamentSection(_ status: LiveParliamentStatus) -> some View {
        Section {
            VStack(alignment: .leading, spacing: EpacSpacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
                    Label(liveBadgeText(for: status), systemImage: liveBadgeIcon(for: status))
                        .font(.epacCaption.weight(.bold))
                        .foregroundStyle(liveBadgeColor(for: status))
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    Button {
                        showLiveInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.epacSubheadline)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.epacText.secondary)
                    .accessibilityLabel(NSLocalizedString("home.live.infoTitle", comment: ""))
                    .popover(isPresented: $showLiveInfo) { liveInfoPopover }
                }

                VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                    Text(liveHeadline(for: status))
                        .font(.epacHeadline)
                        .foregroundStyle(Color.epacText.primary)
                        .lineLimit(2)
                    Text(liveDetail(for: status))
                        .font(.epacSubheadline)
                        .foregroundStyle(Color.epacText.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: EpacSpacing.s) {
                    Text(String(
                        format: NSLocalizedString("home.live.updated", comment: ""),
                        status.checkedAt.formatted(date: .omitted, time: .shortened)
                    ))
                    if let billNumber = status.currentBillNumber {
                        Text(billNumber)
                    }
                }
                .font(.epacCaption)
                .foregroundStyle(Color.epacText.tertiary)
            }
            .padding(.vertical, EpacSpacing.s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home-live-parliament-card")
        }
    }

    private func postSittingSection(hansard: Hansard, subject: SubjectOfBusiness) -> some View {
        Section {
            NavigationLink(destination: SpeechView(hansard: hansard, subject: subject)) {
                VStack(alignment: .leading, spacing: EpacSpacing.m) {
                    Label(
                        NSLocalizedString("home.live.todayBadge", comment: ""),
                        systemImage: "building.columns.fill"
                    )
                    .font(.epacCaption.weight(.bold))
                    .foregroundStyle(Color.epacBrand.accent)
                    .labelStyle(.titleAndIcon)

                    VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                        Text(hansard.date.formatted(date: .long, time: .omitted))
                            .font(.epacHeadline)
                            .foregroundStyle(Color.epacText.primary)
                        Text(subject.title)
                            .font(.epacSubheadline)
                            .foregroundStyle(Color.epacText.secondary)
                            .lineLimit(2)
                    }

                    Text(NSLocalizedString("home.live.tapToRead", comment: ""))
                        .font(.epacCaption.weight(.semibold))
                        .foregroundStyle(Color.epacBrand.accent)
                }
                .padding(.vertical, EpacSpacing.s)
            }
            .accessibilityIdentifier("home-live-parliament-card")
        }
    }

    private var postSittingPendingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: EpacSpacing.m) {
                Label(
                    NSLocalizedString("home.live.todayBadge", comment: ""),
                    systemImage: "building.columns.fill"
                )
                .font(.epacCaption.weight(.bold))
                .foregroundStyle(Color.epacText.secondary)
                .labelStyle(.titleAndIcon)

                Text(NSLocalizedString("home.live.comingSoon", comment: ""))
                    .font(.epacSubheadline)
                    .foregroundStyle(Color.epacText.secondary)
            }
            .padding(.vertical, EpacSpacing.s)
            .accessibilityIdentifier("home-live-parliament-card")
        }
    }

    private var liveInfoPopover: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.s) {
            Text(NSLocalizedString("home.live.infoTitle", comment: ""))
                .font(.epacHeadline)
            Text(NSLocalizedString("home.live.infoBody", comment: ""))
                .font(.epacCallout)
                .foregroundStyle(Color.epacText.secondary)
        }
        .padding(EpacSpacing.m)
        .frame(maxWidth: 320, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private var todaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: EpacSpacing.m) {
                todayHeader

                if !networkMonitor.isConnected {
                    Label(offlineCacheText, systemImage: "wifi.slash")
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacStatus.warning)
                        .accessibilityIdentifier("homeTodayOfflineState")
                }

                Divider()

                if let vote = latestRecordedVote {
                    todayVoteRow(vote)
                }

                if let highlight = latestSpeechHighlight {
                    NavigationLink(destination: SpeechView(hansard: highlight.hansard, subject: highlight.subject)) {
                        todayMetricRow(
                            icon: "quote.bubble.fill",
                            title: NSLocalizedString("home.today.latestSpeech", comment: ""),
                            headline: highlight.excerpt,
                            detail: "\(highlight.memberName) · \(highlight.hansard.date.formatted(date: .abbreviated, time: .omitted))"
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded { trackTodayCardTap("speech") })
                } else if hasFollowedMPContext {
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
            .accessibilityLabel(parliamentStatusTitle)
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
                Image(systemName: parliamentStatusIcon)
                    .foregroundStyle(parliamentStatusColor)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                    Text(parliamentStatusTitle)
                        .font(.epacHeadline)
                        .foregroundStyle(parliamentStatusColor)
                    Text(todayStatusDetail)
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
    private func todayVoteRow(_ vote: RecordedVote) -> some View {
        if let memberVote = latestMemberVote {
            NavigationLink(destination: VoteDetailView(mv: memberVote, rv: vote)) {
                todayMetricRow(
                    icon: "checkmark.ballot.fill",
                    title: NSLocalizedString("home.today.latestVote", comment: ""),
                    headline: vote.descriptionEn.isEmpty ? "Vote #\(vote.number)" : vote.descriptionEn,
                    detail: voteSummary(vote, memberVote: memberVote)
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

    private func todayMetricRow(icon: String, title: String, headline: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: EpacSpacing.s) {
            Image(systemName: icon)
                .foregroundStyle(Color.epacBrand.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                Text(title)
                    .font(.epacCaption.weight(.semibold))
                    .foregroundStyle(Color.epacText.secondary)
                Text(headline)
                    .font(.epacSubheadline.weight(.semibold))
                    .foregroundStyle(Color.epacText.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Section 2: Your MP's activity

    private var myMPSection: some View {
        Section {
            if let name = PostalCodeViewModel.savedMemberName {
                NavigationLink(destination: MyMPView()) {
                    HStack {
                        Image(systemName: "person.fill.viewfinder")
                            .foregroundStyle(Color.epacBrand.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                            Text(name)
                                .font(.epacSubheadline.weight(.semibold))
                                .lineLimit(2)
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

    // MARK: - Section 3: Followed bills

    private var followedBillsSection: some View {
        Section(header: Text(NSLocalizedString("home.followedBills", comment: "")).accessibilityAddTraits(.isHeader)) {
            let sorted = billStore.followed.sorted { $0.value.followedAt > $1.value.followedAt }
            ForEach(Array(sorted.prefix(3)), id: \.key) { number, state in
                HStack {
                    Image(systemName: "doc.badge.clock.fill")
                        .foregroundStyle(Color.epacBrand.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                        Text(number)
                            .font(.epacSubheadline.weight(.semibold))
                        Text(state.lastKnownStage)
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacText.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bill \(number), \(state.lastKnownStage), Followed")
            }
            HStack {
                NavigationLink(destination: BillsView()) {
                    Text(NSLocalizedString("home.seeAllBills", comment: ""))
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacBrand.accent)
                }
                if billStore.followed.count > 3 {
                    Spacer()
                    Button {
                        billStore.unfollowAll()
                    } label: {
                        Text(NSLocalizedString("home.clearAllBills", comment: ""))
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacStatus.destructive)
                    }
                    .accessibilityLabel("Unfollow all bills")
                }
            }
        }
    }

    // MARK: - Section 4: Followed topics

    private var followedTopicsSection: some View {
        Section(header: Text(NSLocalizedString("home.followedTopics", comment: "")).accessibilityAddTraits(.isHeader)) {
            let followedTopics = ParliamentaryTopic.all.filter { topicStore.isFollowing($0.id) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: EpacSpacing.s) {
                    ForEach(followedTopics.prefix(6)) { topic in
                        Text(topic.localizedName)
                            .font(.epacCaption.weight(.medium))
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
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacBrand.accent)
            }
        }
    }

    // MARK: - Section 4b: My Senators (shown when province is known)

    private var senatorsSection: some View {
        Section(header: Text(NSLocalizedString("senate.mySenators.title", comment: "")).accessibilityAddTraits(.isHeader)) {
            ForEach(mySenators.prefix(3)) { senator in
                Link(destination: senator.senateURL) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(senator.caucusColor.opacity(0.2))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(senator.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(senator.caucusFullName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacText.tertiary)
                    }
                }
                .accessibilityLabel("\(senator.name), \(senator.caucusFullName)")
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
                        ForEach(healthData.prefix(2), id: \.procedure) { wt in
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
            ForEach(recentSubjects) { subject in
                Text(subject.title)
                    .font(.epacSubheadline)
                    .lineLimit(2)
                    .padding(.vertical, EpacSpacing.xs)
            }
            if latestHansard != nil {
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
        // Section 1: Check sitting calendar
        let today = Calendar.current.startOfDay(for: Date())
        let calendars = (try? modelContext.fetch(FetchDescriptor<SittingCalendar>())) ?? []
        let allSittingDates = calendars.flatMap(\.sittings).map { Calendar.current.startOfDay(for: $0) }
        isSittingToday = allSittingDates.contains { Calendar.current.isDate($0, inSameDayAs: today) }
        nextSittingDate = allSittingDates.filter { $0 > today }.sorted().first

        // Section 2: Count MP activities (speech messages by last name)
        let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
        let followedMember = resolveFollowedMember(from: allMembers)
        if let name = PostalCodeViewModel.savedMemberName {
            let lastName = name.components(separatedBy: " ").last ?? name
            let msgs = (try? modelContext.fetch(FetchDescriptor<SpeechMessage>())) ?? []
            myMPActivityCount = msgs.filter {
                $0.lastName.localizedCaseInsensitiveContains(lastName)
            }.count

            // Resolve province for healthcare contextual card
            if let mp = followedMember {
                provinceAbbrev = mp.province.shortCode
                // Load senators for the user's province if not already loaded.
                if mySenators.isEmpty && !provinceAbbrev.isEmpty {
                    let allSenators = await SenatorsService.fetchSenators()
                    mySenators = SenatorsService.senators(for: provinceAbbrev, from: allSenators)
                }
            }
        }

        // Section 5: Recent subjects from latest Hansard
        let hansards = (try? modelContext.fetch(FetchDescriptor<Hansard>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        latestHansard = hansards.first
        parliamentDayStatus = resolveParliamentDayStatus(today: today, latestHansard: latestHansard)
        if liveParliamentStatus?.isSitting == true {
            parliamentDayStatus = .sitting
        }
        recentSubjects = Array(
            (hansards.first?.orders.flatMap { $0.subjects } ?? []).prefix(3)
        )
        latestSpeechHighlight = makeLatestSpeechHighlight(for: followedMember, in: hansards)

        var voteDescriptor = FetchDescriptor<RecordedVote>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        voteDescriptor.fetchLimit = 1
        latestRecordedVote = (try? modelContext.fetch(voteDescriptor))?.first

        if let memberID = followedMember?.memberID, let voteID = latestRecordedVote?.voteID {
            var memberVoteDescriptor = FetchDescriptor<MemberVote>(
                predicate: #Predicate<MemberVote> { $0.memberID == memberID && $0.voteID == voteID },
                sortBy: [SortDescriptor(\.voteID, order: .reverse)]
            )
            memberVoteDescriptor.fetchLimit = 1
            latestMemberVote = (try? modelContext.fetch(memberVoteDescriptor))?.first
        } else {
            latestMemberVote = nil
        }
    }

    private func pollLiveParliamentStatus(while phase: ScenePhase) async {
        guard phase == .active else { return }
        await refreshLiveParliamentStatus()
        while !Task.isCancelled {
            do {
                let interval: Double = livePollingInterval
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
            await refreshLiveParliamentStatus()
        }
    }

    private var livePollingInterval: Double {
        guard let status = liveParliamentStatus, !status.isSitting,
              let changedAt = status.lastChangedAt else {
            return 120
        }
        // After a sitting ends and > 6h have elapsed, slow to hourly to
        // conserve resources while we wait for Hansard to publish.
        return Date().timeIntervalSince(changedAt) > 6 * 3600 ? 3600 : 120
    }

    private func refreshLiveParliamentStatus() async {
        guard networkMonitor.isConnected else { return }
        do {
            let status = try await liveParliamentService.fetchStatus()
            liveParliamentStatus = status
            if status.isSitting {
                parliamentDayStatus = .sitting
            }
            resolvePostSittingHansard(for: status)
        } catch {
            Log.error("HomeFeedView live status refresh failed: \(error.localizedDescription)")
        }
    }

    private func resolvePostSittingHansard(for status: LiveParliamentStatus) {
        guard !status.isSitting, let sittingDate = status.sittingDate else {
            postSittingHansard = nil
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        guard let date = formatter.date(from: sittingDate) else {
            postSittingHansard = nil
            return
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<Hansard>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        postSittingHansard = (try? modelContext.fetch(descriptor))?.first
    }

    // Returns today's date string (YYYY-MM-DD) in Ottawa local time.
    private var ottawaTodayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        return formatter.string(from: Date())
    }

    private enum LiveCardState {
        case live(LiveParliamentStatus)
        case todayPublished(Hansard, SubjectOfBusiness)
        case todayPending
        case hidden
    }

    private var liveCardState: LiveCardState {
        guard let status = liveParliamentStatus else { return .hidden }
        if status.isSitting { return .live(status) }
        guard let sittingDate = status.sittingDate, sittingDate == ottawaTodayString else {
            return .hidden
        }
        if let hansard = postSittingHansard,
           let subject = hansard.orders.first?.subjects.first {
            return .todayPublished(hansard, subject)
        }
        return .todayPending
    }

    private var todayStatusDetail: String {
        if parliamentDayStatus == .sitting {
            return Date().formatted(date: .abbreviated, time: .omitted)
        }
        if parliamentDayStatus == .adjourned, let latestHansard {
            return String(
                format: NSLocalizedString("home.today.adjournedDetail", comment: ""),
                latestHansard.date.formatted(date: .abbreviated, time: .omitted)
            )
        }
        if let nextSittingDate {
            return String(
                format: NSLocalizedString("home.today.nextSitting", comment: ""),
                nextSittingDate.formatted(date: .abbreviated, time: .omitted)
            )
        }
        return NSLocalizedString("home.today.noCalendar", comment: "")
    }

    private var parliamentStatusTitle: String {
        switch parliamentDayStatus {
        case .sitting:
            return NSLocalizedString("home.parliament.sitting", comment: "")
        case .adjourned:
            return NSLocalizedString("home.parliament.adjourned", comment: "")
        case .notSitting:
            return NSLocalizedString("home.parliament.notSitting", comment: "")
        }
    }

    private var parliamentStatusIcon: String {
        switch parliamentDayStatus {
        case .sitting, .adjourned:
            return "building.columns.fill"
        case .notSitting:
            return "building.columns"
        }
    }

    private var parliamentStatusColor: Color {
        switch parliamentDayStatus {
        case .sitting:
            return Color.epacBrand.accent
        case .adjourned:
            return Color.epacStatus.warning
        case .notSitting:
            return Color.epacText.secondary
        }
    }

    private func liveBadgeText(for status: LiveParliamentStatus) -> String {
        status.divisionInProgress
            ? NSLocalizedString("home.live.voteBadge", comment: "")
            : NSLocalizedString("home.live.badge", comment: "")
    }

    private func liveBadgeIcon(for status: LiveParliamentStatus) -> String {
        status.divisionInProgress ? "checkmark.ballot.fill" : "circle.fill"
    }

    private func liveBadgeColor(for status: LiveParliamentStatus) -> Color {
        status.divisionInProgress ? Color.epacStatus.warning : Color.epacStatus.destructive
    }

    private func liveHeadline(for status: LiveParliamentStatus) -> String {
        if let title = status.currentItemTitle, !title.isEmpty {
            return title
        }
        return status.businessType
    }

    private func liveDetail(for status: LiveParliamentStatus) -> String {
        if status.divisionInProgress {
            return NSLocalizedString("home.live.resultIncoming", comment: "")
        }
        if let speaker = status.currentSpeakerName, !speaker.isEmpty {
            return String(format: NSLocalizedString("home.live.speaker", comment: ""), speaker)
        }
        return String(
            format: NSLocalizedString("home.live.updated", comment: ""),
            status.checkedAt.formatted(date: .omitted, time: .shortened)
        )
    }

    private var hasFollowedMPContext: Bool {
        PostalCodeViewModel.savedMemberName != nil || !MemberFollowStore.shared.followedIDs.isEmpty
    }

    private var offlineCacheText: String {
        let syncDates = [
            UserDefaults.standard.object(forKey: "epac.sync.hansard") as? Date,
            UserDefaults.standard.object(forKey: "epac.sync.votes") as? Date,
            latestHansard?.date
        ].compactMap { $0 }
        guard let lastSync = syncDates.max() else {
            return NSLocalizedString("home.today.offline", comment: "")
        }
        return String(
            format: NSLocalizedString("home.today.offlineCache", comment: ""),
            lastSync.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func voteSummary(_ vote: RecordedVote, memberVote: MemberVote?) -> String {
        var parts: [String] = []
        if !vote.billNumberCode.isEmpty { parts.append(vote.billNumberCode) }
        if !vote.resultEn.isEmpty { parts.append(vote.resultEn) }
        parts.append("\(NSLocalizedString("votes.yea", comment: "")) \(vote.yea) · \(NSLocalizedString("votes.nay", comment: "")) \(vote.nay)")
        if let memberVote {
            parts.append(String(format: NSLocalizedString("home.today.myMPBallot", comment: ""), memberVote.recordedVote))
        }
        return parts.joined(separator: " · ")
    }

    private func resolveFollowedMember(from members: [ParliamentMember]) -> ParliamentMember? {
        if let savedName = PostalCodeViewModel.savedMemberName,
           let match = members.first(where: {
               $0.name.localizedCaseInsensitiveContains(savedName) ||
               savedName.localizedCaseInsensitiveContains($0.lastName)
           }) {
            return match
        }
        if let followedID = MemberFollowStore.shared.followedIDs.first {
            return members.first { $0.memberID == followedID }
        }
        return nil
    }

    private func resolveParliamentDayStatus(today: Date, latestHansard: Hansard?) -> HomeParliamentDayStatus {
        guard isSittingToday else { return .notSitting }
        if let latestHansard, Calendar.current.isDate(latestHansard.date, inSameDayAs: today) {
            return .adjourned
        }
        return .sitting
    }

    private func makeLatestSpeechHighlight(for member: ParliamentMember?, in hansards: [Hansard]) -> HomeSpeechHighlight? {
        guard let member else { return nil }
        let memberLastName = member.lastName
        for hansard in hansards.prefix(20) {
            for subject in hansard.orders.flatMap(\.subjects) {
                for speech in subject.speeches {
                    if let message = speech.messages.first(where: {
                        $0.lastName.localizedCaseInsensitiveCompare(memberLastName) == .orderedSame ||
                        member.name.localizedCaseInsensitiveContains($0.lastName)
                    }) {
                        return HomeSpeechHighlight(
                            hansard: hansard,
                            subject: subject,
                            memberName: member.name,
                            excerpt: Self.trimmedExcerpt(message.content)
                        )
                    }
                }
            }
        }
        return nil
    }

    private static func trimmedExcerpt(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 140 else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: 140)
        return String(cleaned[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func yearOverYearLabel(_ value: Double) -> String {
        if value > 0 {
            return "+\(value.formatted(.number.precision(.fractionLength(1))))%"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func trackTodayCardTap(_ target: String) {
        Log.info("home.today.tap target=\(target)")
    }
}

private struct HomeSpeechHighlight {
    let hansard: Hansard
    let subject: SubjectOfBusiness
    let memberName: String
    let excerpt: String
}

private enum HomeParliamentDayStatus {
    case sitting
    case adjourned
    case notSitting
}
