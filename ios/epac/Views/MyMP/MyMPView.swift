//
//  MyMPView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftData
import SwiftUI

// MARK: - Activity model

private enum MPActivity: Identifiable {
    case speech(Speech)
    case vote(MemberVote, RecordedVote?)
    case expenditure(SummaryExpenditure)

    var id: String {
        switch self {
        case .speech(let s):       return "speech-\(s.hansardID)"
        case .vote(let mv, _):     return "vote-\(mv.memberID)-\(mv.voteID)"
        case .expenditure(let e):  return "exp-\(e.firstName)-\(e.lastName)-\(e.year)-\(e.quarter)"
        }
    }

    var date: Date {
        switch self {
        case .speech(let s):
            return s.date
        case .vote(_, let rv):
            return rv?.date ?? .distantPast
        case .expenditure(let e):
            return Calendar.current.date(from: DateComponents(year: e.year, month: e.quarter * 3)) ?? .distantPast
        }
    }

    var systemImage: String {
        switch self {
        case .speech:       return "bubble.left.fill"
        case .vote:         return "checkmark.square.fill"
        case .expenditure:  return "dollarsign.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .speech:
            return Color.epacBrand.accent
        case .vote(let mv, _):
            return Color.ballot(mv.recordedVote)
        case .expenditure:
            return Color.epacStatus.info
        }
    }

    var title: String {
        switch self {
        case .speech(let s):
            return s.title.isEmpty
                ? NSLocalizedString("myMP.activity.speech", comment: "")
                : s.title
        case .vote(let mv, let rv):
            let bill = (rv?.billNumberCode.isEmpty == false) ? rv?.billNumberCode ?? "Vote #\(mv.voteID)" : "Vote #\(mv.voteID)"
            return "\(bill) — \(mv.recordedVote)"
        case .expenditure(let e):
            return String(format: NSLocalizedString("myMP.activity.expenditure", comment: ""), e.year, e.quarter)
        }
    }
}

// MARK: - Activity row

private struct ActivityRow: View {
    let activity: MPActivity

    var body: some View {
        HStack(alignment: .top, spacing: EpacSpacing.s) {
            Image(systemName: activity.systemImage)
                .foregroundStyle(activity.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                Text(activity.title)
                    .font(.epacSubheadline)
                    .lineLimit(2)
                if activity.date > Date.distantPast {
                    Text(activity.date, style: .date)
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacText.secondary)
                }
            }
        }
        .padding(.vertical, EpacSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - MyMPView

struct MyMPView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var member: ParliamentMember?
    @State private var activities: [MPActivity] = []
    @State private var isLoading = false
    @State private var showPostalCodeSetup = false
    @State private var followStore = MemberFollowStore.shared
    @State private var showConsultations = false
    @State private var showElectionResources = false
    @State private var senators: [Senator] = []
    @State private var senatorsLoaded = false
    @State private var ontarioMPP: OntarioMPP?
    @State private var vancouverCouncillors: [VancouverCouncillor] = []
    @State private var showVancouverVotes = false
    @State private var torontoCouncillors: [TorontoCouncillor] = []
    @State private var showTorontoVotes = false

    var body: some View {
        NavigationStack {
            Group {
                if PostalCodeViewModel.savedMemberName == nil && followStore.followedIDs.isEmpty {
                    // No postal code and no followed members → prompt to set up
                    noMPSetView
                } else if isLoading && activities.isEmpty {
                    ProgressView()
                } else if activities.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: NSLocalizedString("myMP.empty.title", comment: ""),
                        message: NSLocalizedString("myMP.empty.description", comment: ""),
                        action: nil
                    )
                } else {
                    activityList
                }
            }
            .navigationTitle(PostalCodeViewModel.savedMemberName ?? NSLocalizedString("myMP.navTitle", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showConsultations = true
                        } label: {
                            Label(NSLocalizedString("consult.navTitle", comment: ""), systemImage: "bubble.left.and.text.bubble.right")
                        }
                        Button {
                            showElectionResources = true
                        } label: {
                            Label(NSLocalizedString("election.navTitle", comment: ""), systemImage: "checklist")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showConsultations) {
                GovernmentConsultationsView()
            }
            .navigationDestination(isPresented: $showElectionResources) {
                ElectionResourcesView()
            }
            .navigationDestination(isPresented: $showVancouverVotes) {
                VancouverVotesView()
            }
            .navigationDestination(isPresented: $showTorontoVotes) {
                TorontoVotesView()
            }
            .task { await loadActivities() }
        }
        .sheet(isPresented: $showPostalCodeSetup) {
            PostalCodeSetupView { showPostalCodeSetup = false }
        }
    }

    // MARK: - Subviews

    private var noMPSetView: some View {
        EmptyStateView(
            icon: "mappin.and.ellipse",
            title: NSLocalizedString("myMP.noMP.title", comment: ""),
            message: NSLocalizedString("myMP.noMP.description", comment: ""),
            action: EmptyStateAction(
                label: NSLocalizedString("riding.setup.lookupButton", comment: ""),
                handler: { showPostalCodeSetup = true }
            )
        )
    }

    private var activityList: some View {
        List {
            Section(NSLocalizedString("bills.navTitle", comment: "")) {
                NavigationLink(destination: BillsView()) {
                    Label(
                        NSLocalizedString("bills.browseAll", comment: ""),
                        systemImage: "doc.text"
                    )
                }
            }
            Section(NSLocalizedString("petitions.navTitle", comment: "")) {
                NavigationLink(destination: PetitionsView()) {
                    Label(
                        NSLocalizedString("petitions.browseAll", comment: ""),
                        systemImage: "person.wave.2"
                    )
                }
            }
            Section(NSLocalizedString("topics.navTitle", comment: "")) {
                NavigationLink(destination: TopicsView()) {
                    Label(
                        NSLocalizedString("topics.browseAll", comment: ""),
                        systemImage: "tag"
                    )
                }
            }
            if !senators.isEmpty {
                Section(NSLocalizedString("senate.mySenators.title", comment: "")) {
                    ForEach(senators) { senator in
                        SenatorCard(senator: senator)
                    }
                }
            } else if senatorsLoaded {
                Section(NSLocalizedString("senate.mySenators.title", comment: "")) {
                    Text(NSLocalizedString("senate.mySenators.empty", comment: ""))
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacText.secondary)
                }
            }
            if let mpp = ontarioMPP {
                Section(NSLocalizedString("ontario.myMPP.title", comment: "")) {
                    OntarioMPPCard(mpp: mpp)
                }
            }
            if let member {
                Section("Riding boundary") {
                    RidingBoundaryMapCard(ridingName: member.riding, party: member.party)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }
            if !vancouverCouncillors.isEmpty {
                Section(NSLocalizedString("vancouver.myCouncil.title", comment: "")) {
                    ForEach(vancouverCouncillors) { councillor in
                        VancouverCouncillorCard(councillor: councillor)
                    }
                    Button {
                        showVancouverVotes = true
                    } label: {
                        Label(NSLocalizedString("vancouver.votes.browseButton", comment: ""),
                              systemImage: "building.2")
                    }
                }
            }
            if !torontoCouncillors.isEmpty {
                Section(NSLocalizedString("toronto.myCouncil.title", comment: "")) {
                    ForEach(torontoCouncillors) { councillor in
                        TorontoCouncillorCard(councillor: councillor)
                    }
                    Button {
                        showTorontoVotes = true
                    } label: {
                        Label(NSLocalizedString("toronto.votes.browseButton", comment: ""),
                              systemImage: "building.2")
                    }
                }
            }
            Section(NSLocalizedString("myMP.activity.section", comment: "")) {
                ForEach(activities) { activity in
                    ActivityRow(activity: activity)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Data loading

    @MainActor
    private func loadActivities() async {
        isLoading = true
        defer { isLoading = false }

        let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []

        // Resolve the saved MP (may be nil if no postal code set)
        var primaryMP: ParliamentMember?
        if let memberName = PostalCodeViewModel.savedMemberName {
            primaryMP = allMembers.first(where: {
                $0.name.localizedCaseInsensitiveContains(memberName) ||
                memberName.localizedCaseInsensitiveContains($0.lastName)
            })
        }
        member = primaryMP

        // Load senators for the primary MP's province
        if let mp = primaryMP {
            let provinceAbbrev = mp.province.shortCode
            if !provinceAbbrev.isEmpty {
                let allSenators = await SenatorsService.fetchSenators()
                senators = SenatorsService.senators(for: provinceAbbrev, from: allSenators)
                senatorsLoaded = true

                // Load Ontario MPP when the federal riding is in Ontario
                if provinceAbbrev == "ON" {
                    let allMPPs = await OntarioLegislatureService.fetchMPPs()
                    // Federal and provincial ridings don't align perfectly; match on
                    // the first significant word of each riding name as a heuristic.
                    if let savedRiding = PostalCodeViewModel.savedRidingName,
                       let firstWord = savedRiding.components(separatedBy: " ").first,
                       !firstWord.isEmpty {
                        ontarioMPP = allMPPs.first { mpp in
                            mpp.riding.localizedCaseInsensitiveContains(firstWord) ||
                            firstWord.localizedCaseInsensitiveContains(mpp.riding.components(separatedBy: " ").first ?? "")
                        }
                    }
                }

                // Load Vancouver City Council when the federal riding is in Vancouver
                if let savedRiding = PostalCodeViewModel.savedRidingName,
                   VancouverCouncilService.isVancouverRiding(savedRiding) {
                    vancouverCouncillors = await VancouverCouncilService.fetchCouncillors()
                }

                // Load Toronto City Council when the federal riding is in Toronto.
                if let savedRiding = PostalCodeViewModel.savedRidingName,
                   TorontoCouncilService.isTorontoRiding(savedRiding) {
                    let councillors = await TorontoCouncilService.fetchCouncillors()
                    torontoCouncillors = TorontoCouncilService.councillors(for: savedRiding, in: councillors)
                }
            }
        }

        // Build the union of members to load: saved MP + all followed MPs
        var memberIDsToShow: Set<Int> = []
        if let mp = primaryMP { memberIDsToShow.insert(mp.memberID) }
        memberIDsToShow.formUnion(followStore.followedIDs)

        guard !memberIDsToShow.isEmpty else { return }

        let mpsToLoad = allMembers.filter { memberIDsToShow.contains($0.memberID) }

        // Fetch all speeches and expenditures once; filter per member below
        let allSpeeches = (try? modelContext.fetch(FetchDescriptor<Speech>())) ?? []
        let allExps = (try? modelContext.fetch(FetchDescriptor<SummaryExpenditure>())) ?? []

        var all: [MPActivity] = []
        for mp in mpsToLoad {
            all += activitiesFor(mp: mp, allSpeeches: allSpeeches, allExps: allExps)
        }

        activities = all.sorted { $0.date > $1.date }
    }

    /// Collects MPActivity items for a single member from pre-fetched speech and expenditure arrays.
    @MainActor
    private func activitiesFor(
        mp: ParliamentMember,
        allSpeeches: [Speech],
        allExps: [SummaryExpenditure]
    ) -> [MPActivity] {
        var result: [MPActivity] = []

        // Speeches: query SpeechMessage by name (predicate-filtered at DB level) to collect
        // matching hansardIDs, then filter the pre-fetched Speech list. This avoids faulting
        // every speech's messages relationship, which would be O(speeches × messages).
        let mpFirstName = mp.firstName
        let mpLastName = mp.lastName
        let firstThreeFirst = String(mpFirstName.prefix(3))

        let matchingMessages = (try? modelContext.fetch(
            FetchDescriptor<SpeechMessage>(predicate: #Predicate {
                $0.lastName == mpLastName
            })
        )) ?? []
        let matchingHansardIDs = Set(
            matchingMessages
                .filter { $0.firstName.localizedCaseInsensitiveContains(firstThreeFirst) }
                .map(\.hansardID)
        )
        if !matchingHansardIDs.isEmpty {
            result += allSpeeches
                .filter { matchingHansardIDs.contains($0.hansardID) }
                .map { .speech($0) }
        }

        // Votes: predicate on memberID
        let mid = mp.memberID
        let votes = (try? modelContext.fetch(FetchDescriptor<MemberVote>(
            predicate: #Predicate { $0.memberID == mid }
        ))) ?? []
        result += votes.map { mv in .vote(mv, mv.vote) }

        // Expenditures: match by last name and first-name prefix
        let myExps = allExps.filter {
            $0.lastName.localizedCaseInsensitiveCompare(mpLastName) == .orderedSame &&
            $0.firstName.localizedCaseInsensitiveContains(firstThreeFirst)
        }
        result += myExps.map { .expenditure($0) }

        return result
    }
}
