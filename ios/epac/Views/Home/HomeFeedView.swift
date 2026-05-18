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

import SwiftData
import SwiftUI

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
    @State private var onThisDayItems: [OnThisDayItem] = []
    @State private var onThisDayDismissedDate = UserDefaults.standard.string(forKey: "epac.onThisDay.dismissedDate") ?? ""
    @State private var didRecordOnThisDayImpression = false
    @State private var selectedOnThisDaySpeech: OnThisDaySpeechSelection?

    private let onThisDayService = OnThisDayService()

    var body: some View {
        NavigationStack {
            List {
                todaySection
                if shouldShowOnThisDaySection {
                    onThisDaySection
                }
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
            }
            .sheet(isPresented: $showPostalCodeSetup) {
                PostalCodeSetupView { showPostalCodeSetup = false }
            }
            .onChange(of: postalCodeStore.savedMemberName) {
                Task { await loadFeed() }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $selectedOnThisDaySpeech) { selection in
                SpeechView(hansard: selection.hansard, subject: selection.subject)
            }
        }
    }

    // MARK: - Section 1: Past debates

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
                .frame(width: 24)
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

    // MARK: - On this day

    private var shouldShowOnThisDaySection: Bool {
        !onThisDayItems.isEmpty && onThisDayDismissedDate != ottawaTodayString
    }

    private var onThisDaySection: some View {
        Section {
            ForEach(onThisDayItems.prefix(5)) { item in
                Button {
                    Task { await openOnThisDayItem(item) }
                } label: {
                    todayMetricRow(
                        icon: item.kind == .vote ? "checkmark.ballot.fill" : "quote.bubble.fill",
                        title: item.detailText,
                        headline: item.title,
                        detail: item.excerpt,
                        detailLineLimit: 1
                    )
                    .padding(.vertical, EpacSpacing.xs)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(NSLocalizedString("home.onThisDay.title", comment: ""))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    dismissOnThisDay()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .accessibilityLabel(NSLocalizedString("home.onThisDay.dismiss", comment: ""))
            }
        }
        .onAppear {
            guard !didRecordOnThisDayImpression else { return }
            didRecordOnThisDayImpression = true
            OnThisDayTelemetry.record(.impression)
        }
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
                            .fixedSize(horizontal: false, vertical: true)
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
                                .fixedSize(horizontal: false, vertical: true)
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
        let useCase = LoadHomeFeed(
            repository: HomeFeedSwiftDataRepository(modelContext: modelContext),
            onThisDayFetching: onThisDayService,
            followPreferenceReading: FollowPreferenceAdapter()
        )
        let snapshot = await useCase.execute(preservingOnThisDayItems: onThisDayItems)

        self.latestVote = snapshot.latestVote
        self.latestMemberVote = snapshot.latestMemberVote
        self.latestSpeechHighlight = snapshot.latestSpeechHighlight
        self.myMPActivityCount = snapshot.myMPActivityCount
        self.recentSubjectTitles = snapshot.recentSubjectTitles
        self.latestHansardDate = snapshot.latestHansardDate

        if self.onThisDayItems != snapshot.onThisDayItems {
            self.didRecordOnThisDayImpression = false
        }
        self.onThisDayItems = snapshot.onThisDayItems

        self.provinceAbbrev = snapshot.civicContext.provinceAbbrev
        self.mySenators = snapshot.civicContext.mySenators
    }

    // Returns today's date string (YYYY-MM-DD) in Ottawa local time.
    private var ottawaTodayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        return formatter.string(from: Date())
    }

    private func dismissOnThisDay() {
        onThisDayDismissedDate = ottawaTodayString
        UserDefaults.standard.set(onThisDayDismissedDate, forKey: "epac.onThisDay.dismissedDate")
        OnThisDayTelemetry.record(.dismiss)
    }

    private var hasPersonalizedContext: Bool {
        postalCodeStore.savedMemberName != nil || !MemberFollowStore.shared.followedIDs.isEmpty
    }

    private var offlineCacheText: String {
        let syncDates = [
            UserDefaults.standard.object(forKey: "epac.sync.hansard") as? Date,
            UserDefaults.standard.object(forKey: "epac.sync.votes") as? Date,
            latestHansardDate
        ].compactMap { $0 }
        guard let lastSync = syncDates.max() else {
            return NSLocalizedString("home.today.offline", comment: "")
        }
        return String(
            format: NSLocalizedString("home.today.offlineCache", comment: ""),
            lastSync.formatted(date: .abbreviated, time: .shortened)
        )
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

    private func openOnThisDayItem(_ item: OnThisDayItem) async {
        OnThisDayTelemetry.record(.tap, itemID: item.id)
        switch item.kind {
        case .speech:
            await openOnThisDaySpeech(item)
        case .vote:
            if let billNumber = item.billNumber, !billNumber.isEmpty {
                router.pendingSearchQuery = billNumber
            } else {
                router.pendingSearchQuery = item.title
            }
            router.selectedTab = .search
        }
    }

    private func openOnThisDaySpeech(_ item: OnThisDayItem) async {
        guard let date = item.parsedDate else {
            router.pendingSearchQuery = item.subjectTitle ?? item.title
            router.selectedTab = .search
            return
        }

        do {
            if resolveHansard(on: date) == nil {
                try await fetch.downloadHansard(date)
            }
            guard let hansard = resolveHansard(on: date),
                  let subject = resolveSubject(for: item, in: hansard) else {
                router.pendingSearchQuery = item.subjectTitle ?? item.title
                router.selectedTab = .search
                return
            }
            prepareOnThisDaySpeechResume(item, subject: subject)
            selectedOnThisDaySpeech = OnThisDaySpeechSelection(hansard: hansard, subject: subject)
        } catch {
            Log.error("HomeFeedView on-this-day speech open failed: \(error.localizedDescription)")
            router.pendingSearchQuery = item.subjectTitle ?? item.title
            router.selectedTab = .search
        }
    }

    private func resolveHansard(on date: Date) -> Hansard? {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        let descriptor = FetchDescriptor<Hansard>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func resolveSubject(for item: OnThisDayItem, in hansard: Hansard) -> SubjectOfBusiness? {
        let subjects = hansard.orders.flatMap(\.subjects)
        if let interventionID = item.interventionID,
           let exact = subjects.first(where: { subject in
               subject.speeches.contains { $0.hansardID == interventionID }
           }) {
            return exact
        }
        if let subjectTitle = item.subjectTitle,
           let titleMatch = subjects.first(where: { $0.title.localizedCaseInsensitiveCompare(subjectTitle) == .orderedSame }) {
            return titleMatch
        }
        return subjects.first
    }

    private func prepareOnThisDaySpeechResume(_ item: OnThisDayItem, subject: SubjectOfBusiness) {
        guard let interventionID = item.interventionID,
              let speech = subject.speeches.first(where: { $0.hansardID == interventionID }) else {
            return
        }
        subject.currentSpeech = speech
        subject.currentSpeechID = speech.hansardID
        speech.currentMessage = nil
        speech.currentMessageID = nil
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

    private func percentLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func trackTodayCardTap(_ target: String) {
        Log.info("home.today.tap target=\(target)")
    }
}

private struct OnThisDaySpeechSelection: Hashable, Identifiable {
    let id = UUID()
    let hansard: Hansard
    let subject: SubjectOfBusiness

    static func == (lhs: OnThisDaySpeechSelection, rhs: OnThisDaySpeechSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
