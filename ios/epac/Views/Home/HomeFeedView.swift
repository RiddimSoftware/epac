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

import SwiftUI
import SwiftData

@MainActor
struct HomeFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isSittingToday = false
    @State private var myMPActivityCount = 0
    @State private var showPostalCodeSetup = false
    @State private var recentSubjects: [SubjectOfBusiness] = []
    @State private var billStore = BillFollowStore.shared
    @State private var topicStore = TopicFollowStore.shared
    @State private var provinceAbbrev: String = ""

    var body: some View {
        NavigationStack {
            List {
                if isSittingToday {
                    todaySection
                }
                myMPSection
                if !billStore.followedNumbers.isEmpty {
                    followedBillsSection
                }
                if !topicStore.followedIDs.isEmpty {
                    followedTopicsSection
                }
                healthcareContextCard
                if !recentSubjects.isEmpty {
                    recentDebatesSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Home", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .task { await loadFeed() }
            .sheet(isPresented: $showPostalCodeSetup) {
                PostalCodeSetupView { showPostalCodeSetup = false }
            }
        }
    }

    // MARK: - Section 1: Today in Parliament

    private var todaySection: some View {
        Section {
            HStack {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("home.parliament.sitting", comment: ""))
                        .font(.subheadline.weight(.semibold))
                    Text(Date(), style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Section 2: Your MP's activity

    private var myMPSection: some View {
        Section {
            if let name = PostalCodeViewModel.savedMemberName {
                NavigationLink(destination: MyMPView()) {
                    HStack {
                        Image(systemName: "person.fill.viewfinder")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(String(format: NSLocalizedString("home.myMP.activityCount", comment: ""), myMPActivityCount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.primary)
            } else {
                Button {
                    showPostalCodeSetup = true
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(NSLocalizedString("home.myMP.notSet", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        Text(NSLocalizedString("riding.setup.lookupButton", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Section 3: Followed bills

    private var followedBillsSection: some View {
        Section(header: Text(NSLocalizedString("home.followedBills", comment: ""))) {
            let sorted = billStore.followed.sorted { $0.value.followedAt > $1.value.followedAt }
            ForEach(Array(sorted.prefix(3)), id: \.key) { number, state in
                HStack {
                    Image(systemName: "doc.badge.clock.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(number)
                            .font(.subheadline.weight(.semibold))
                        Text(state.lastKnownStage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
            NavigationLink(destination: BillsView()) {
                Text(NSLocalizedString("home.seeAllBills", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: - Section 4: Followed topics

    private var followedTopicsSection: some View {
        Section(header: Text(NSLocalizedString("home.followedTopics", comment: ""))) {
            let followedTopics = ParliamentaryTopic.all.filter { topicStore.isFollowing($0.id) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(followedTopics.prefix(6)) { topic in
                        Text(topic.localizedName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
            NavigationLink(destination: TopicsView()) {
                Text(NSLocalizedString("home.manageTopics", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.tint)
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: NSLocalizedString("cihi.contextCard.title", comment: ""), provinceAbbrev))
                            .font(.subheadline.weight(.semibold))
                        ForEach(healthData.prefix(2), id: \.procedure) { wt in
                            HStack {
                                Text(wt.procedure).font(.caption)
                                Spacer()
                                Text("\(Int(wt.medianWeeks))w median").font(.caption.monospacedDigit())
                            }
                        }
                        Link(NSLocalizedString("cihi.viewSource", comment: ""), destination: CIHIWaitTimeDatabase.sourceURL)
                            .font(.caption2)
                    }
                } header: {
                    Text(NSLocalizedString("cihi.sectionTitle.short", comment: ""))
                }
            }
        }
    }

    // MARK: - Section 5: Recent debates

    private var recentDebatesSection: some View {
        Section(header: Text(NSLocalizedString("home.recentDebates", comment: ""))) {
            ForEach(recentSubjects) { subject in
                Text(subject.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Data loading

    private func loadFeed() async {
        // Section 1: Check sitting calendar
        let today = Calendar.current.startOfDay(for: Date())
        let calendars = (try? modelContext.fetch(FetchDescriptor<SittingCalendar>())) ?? []
        isSittingToday = calendars.contains {
            $0.sittings.contains { Calendar.current.isDate($0, inSameDayAs: today) }
        }

        // Section 2: Count MP activities (speech messages by last name)
        if let name = PostalCodeViewModel.savedMemberName {
            let lastName = name.components(separatedBy: " ").last ?? name
            let msgs = (try? modelContext.fetch(FetchDescriptor<SpeechMessage>())) ?? []
            myMPActivityCount = msgs.filter {
                $0.lastName.localizedCaseInsensitiveContains(lastName)
            }.count

            // Resolve province for healthcare contextual card
            let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
            if let mp = allMembers.first(where: {
                $0.name.localizedCaseInsensitiveContains(name) ||
                name.localizedCaseInsensitiveContains($0.lastName)
            }) {
                provinceAbbrev = mp.province.shortCode
            }
        }

        // Section 5: Recent subjects from latest Hansard
        let hansards = (try? modelContext.fetch(FetchDescriptor<Hansard>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        recentSubjects = Array(
            (hansards.first?.orders.flatMap { $0.subjects } ?? []).prefix(3)
        )
    }
}
