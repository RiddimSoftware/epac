//
//  BillDetailView.swift
//  epac
//
//  Created on 2026-04-27.
//

import ActivityView
import SwiftData
import SwiftUI

private enum BillDetailLayout {
    static let timelineRowSpacing: CGFloat = 12
    static let timelineTextSpacing = EpacSpacing.xxs
    static let voteTextSpacing = EpacSpacing.xxs
    static let headerSpacing: CGFloat = 10
    static let headerBadgeSpacing = EpacSpacing.s
    static let headerBadgeColumnSpacing: CGFloat = 6
    static let headerSpacerLength = EpacSpacing.s
    static let accentBadgeOpacity = 0.85
    static let sponsorRowSpacing: CGFloat = 6
    static let sponsorMatchPrefixLength = 3
    static let badgeHorizontalPadding: CGFloat = 6
    static let badgeVerticalPadding: CGFloat = 3
}

struct BillDetailView: View {
    let bill: Bill
    @Environment(\.modelContext) private var modelContext

    private let loadBillLobbyingContext: LoadBillLobbyingContext
    private let loadBillCommitteeStage: LoadBillCommitteeStage
    private let loadBillAmendments: LoadBillAmendments
    private let autoloadLobbyingContext: Bool
    private let autoloadCommitteeStage: Bool
    private let autoloadAmendments: Bool

    @State private var billStore = BillFollowStore.shared
    @State private var matchingVotes: [RecordedVote] = []
    @State private var matchingDebates: [SubjectOfBusiness] = []
    @State private var lobbyingContext: BillLobbyingContext?
    @State private var committeeStage: BillCommitteeStage?
    @State private var amendments: [BillAmendment] = []
    @State private var amendmentsLoaded = false
    @State private var memberRoster: [ParliamentMember] = []
    @State private var shareItem: ActivityItem?
    @State private var myMP: ParliamentMember?
    @State private var sponsorMember: ParliamentMember?

    init(
        bill: Bill,
        loadBillLobbyingContext: LoadBillLobbyingContext = LoadBillLobbyingContext(
            repository: BackendBillLobbyingContextRepository()
        ),
        loadBillCommitteeStage: LoadBillCommitteeStage = LoadBillCommitteeStage(
            repository: BackendBillCommitteeStageRepository()
        ),
        loadBillAmendments: LoadBillAmendments = LoadBillAmendments(
            repository: BackendBillAmendmentsRepository()
        ),
        autoloadLobbyingContext: Bool = true,
        autoloadCommitteeStage: Bool = true,
        autoloadAmendments: Bool = true
    ) {
        self.bill = bill
        self.loadBillLobbyingContext = loadBillLobbyingContext
        self.loadBillCommitteeStage = loadBillCommitteeStage
        self.loadBillAmendments = loadBillAmendments
        self.autoloadLobbyingContext = autoloadLobbyingContext
        self.autoloadCommitteeStage = autoloadCommitteeStage
        self.autoloadAmendments = autoloadAmendments
    }

    var body: some View {
        List {
            billHeaderSection

            if bill.type == .privateMember || bill.type == .senatePublic || bill.type == .senatePrivate {
                pmbExplanationSection
            }

            keyFactsSection

            // MARK: PBO independent cost analysis
            PBOCostCard(bill: bill)

            // MARK: Committee study stage
            if let committeeStage {
                BillInCommitteePanel(stage: committeeStage)
            }

            // MARK: Amendments tabled
            if amendmentsLoaded {
                BillAmendmentsPanel(amendments: amendments, memberRoster: memberRoster)
            }

            // MARK: Pre-vote lobbying context
            if let lobbyingContext {
                BillLobbyingContextPanel(context: lobbyingContext)
            }

            // MARK: Stage timeline
            Section(NSLocalizedString("bills.detail.timeline", comment: "")) {
                ForEach(Array(bill.stages.enumerated()), id: \.element.id) { index, stage in
                    let state = timelineState(forStageAt: index)
                    HStack(spacing: BillDetailLayout.timelineRowSpacing) {
                        Image(systemName: state.systemImage)
                            .foregroundStyle(state.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: BillDetailLayout.timelineTextSpacing) {
                            Text(stage.name)
                                .font(.subheadline)
                                .fontWeight(state == .current ? .semibold : .regular)
                                .explainerTip(for: stage.name)
                            if let date = stage.completedDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(state.displayName)
                                    .font(.caption2.weight(state == .current ? .semibold : .regular))
                                    .foregroundStyle(state == .current ? Color.accentColor : .secondary)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel({
                        if let date = stage.completedDate {
                            return "\(stage.name), \(state.accessibilityStatus), \(date.formatted(date: .abbreviated, time: .omitted))"
                        }
                        return "\(stage.name), \(state.accessibilityStatus)"
                    }())
                }
            }

            // MARK: Recorded votes on this bill
            if !matchingVotes.isEmpty {
                Section(NSLocalizedString("bills.detail.votes", comment: "")) {
                    ForEach(matchingVotes, id: \.voteID) { vote in
                        VStack(alignment: .leading, spacing: BillDetailLayout.voteTextSpacing) {
                            Text(vote.descriptionEn)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Text(vote.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(NSLocalizedString("votes.yea", comment: "")) \(vote.yea) / \(NSLocalizedString("votes.nay", comment: "")) \(vote.nay)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            // MARK: Hansard debates mentioning this bill
            if !matchingDebates.isEmpty {
                Section(NSLocalizedString("bills.detail.debates", comment: "")) {
                    ForEach(matchingDebates, id: \.hansardID) { subject in
                        Text(subject.title)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // MARK: Actions
            Section {
                ContactMyMPButton(
                    myMP: myMP,
                    template: ContactMyMP.billTemplate(bill: bill)
                )
                Link(NSLocalizedString("bills.detail.legisinfo", comment: ""),
                     destination: bill.legisInfoURL)
                    .foregroundStyle(Color.accentColor)
            }

            // MARK: Data source badge
            Section {
                HStack {
                    Spacer()
                    DataSourceBadge(source: .bills())
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .adaptiveReadingWidth()
        .navigationTitle(bill.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    shareItem = BillSharer.activityItem(for: bill)
                } label: {
                    Label(NSLocalizedString("bill.share", comment: ""), systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(NSLocalizedString("bill.share", comment: ""))

                Button {
                    billStore.toggle(bill)
                    HapticEngine.light()
                } label: {
                    Label(
                        billStore.isFollowing(bill.number)
                            ? NSLocalizedString("bill.unfollow", comment: "")
                            : NSLocalizedString("bill.follow", comment: ""),
                        systemImage: billStore.isFollowing(bill.number) ? "doc.badge.clock.fill" : "doc.badge.clock"
                    )
                }
                .accessibilityLabel(billStore.isFollowing(bill.number)
                    ? NSLocalizedString("bill.unfollow", comment: "")
                    : NSLocalizedString("bill.follow", comment: ""))
            }
        }
        .task {
            await loadCrossReferences()
            await loadCommitteeStage()
            await loadAmendments()
            await loadLobbyingContext()
            BillFollowStore.shared.markAsRead(bill.number)
        }
        .activitySheet($shareItem)
    }

    private var billHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BillDetailLayout.headerSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: BillDetailLayout.headerBadgeSpacing) {
                        billNumberHeader
                        Spacer(minLength: BillDetailLayout.headerSpacerLength)
                        headerBadges
                    }
                    VStack(alignment: .leading, spacing: BillDetailLayout.headerBadgeSpacing) {
                        billNumberHeader
                        headerBadges
                    }
                }

                Text(bill.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if !bill.currentStage.isEmpty {
                    Text(bill.currentStage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .explainerTip(for: bill.currentStage)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel)
        }
    }

    private var billNumberHeader: some View {
        Text(bill.number)
            .font(.title3.weight(.semibold).monospacedDigit())
    }

    @ViewBuilder
    private var headerBadges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: BillDetailLayout.headerBadgeSpacing) {
                if !bill.type.shortName.isEmpty {
                    BillHeaderBadge(
                        text: bill.type.shortName,
                        foreground: .white,
                        background: Color.accentColor.opacity(BillDetailLayout.accentBadgeOpacity)
                    )
                }
                BillHeaderBadge(
                    text: bill.status.displayName,
                    foreground: .white,
                    background: bill.status.color
                )
            }
            VStack(alignment: .leading, spacing: BillDetailLayout.headerBadgeColumnSpacing) {
                if !bill.type.shortName.isEmpty {
                    BillHeaderBadge(
                        text: bill.type.shortName,
                        foreground: .white,
                        background: Color.accentColor.opacity(BillDetailLayout.accentBadgeOpacity)
                    )
                }
                BillHeaderBadge(
                    text: bill.status.displayName,
                    foreground: .white,
                    background: bill.status.color
                )
            }
        }
    }

    private var keyFactsSection: some View {
        Section(NSLocalizedString("bills.detail.keyFacts", comment: "")) {
            if !bill.sponsorName.isEmpty {
                LabeledContent(NSLocalizedString("bills.detail.sponsor", comment: "")) {
                    HStack(spacing: BillDetailLayout.sponsorRowSpacing) {
                        Text(bill.sponsorName)
                        if let party = sponsorMember?.party {
                            NavigationLink(destination: partyDestination(for: party)) {
                                PartyBadge(party: party)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("bill-detail-party-link")
                        }
                    }
                }
            }
            if let chamber = originatingChamberName {
                LabeledContent(NSLocalizedString("bills.detail.originatingChamber", comment: ""), value: chamber)
            }
            if let introduced = bill.introducedDate {
                LabeledContent(
                    NSLocalizedString("bills.detail.introduced", comment: ""),
                    value: introduced.formatted(date: .abbreviated, time: .omitted)
                )
            }
            if !bill.currentStage.isEmpty {
                LabeledContent(NSLocalizedString("bills.detail.stage", comment: "")) {
                    Text(bill.currentStage)
                        .explainerTip(for: bill.currentStage)
                }
            }
            if !bill.type.displayName.isEmpty {
                LabeledContent(NSLocalizedString("bills.detail.type", comment: "")) {
                    Text(bill.type.displayName)
                        .explainerTip(for: bill.type.displayName)
                }
            }
            LabeledContent(
                NSLocalizedString("bills.detail.parliament", comment: ""),
                value: String(format: NSLocalizedString("bills.detail.parliament.value", comment: ""),
                              bill.parliament, bill.session)
            )
            Link(NSLocalizedString("bills.detail.legisinfo", comment: ""), destination: bill.legisInfoURL)
                .foregroundStyle(Color.accentColor)
        }
    }

    private var pmbExplanationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                HStack(alignment: .top, spacing: EpacSpacing.s) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                        Text(NSLocalizedString("bills.detail.pmb.title", comment: ""))
                            .font(.subheadline.bold())

                        Text(NSLocalizedString("bills.detail.pmb.explanation", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var originatingChamberName: String? {
        if bill.number.uppercased().hasPrefix("C-") {
            return NSLocalizedString("bills.chamber.house", comment: "")
        } else if bill.number.uppercased().hasPrefix("S-") {
            return NSLocalizedString("bills.chamber.senate", comment: "")
        }
        return nil
    }

    @ViewBuilder
    private func partyDestination(for party: Party) -> some View {
        if party == .independent {
            IndependentsListingView()
        } else {
            PartyProfileView(party: party)
        }
    }

    private var headerAccessibilityLabel: String {
        [
            bill.number,
            bill.title,
            bill.status.displayName,
            bill.type.displayName,
            bill.currentStage
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private func timelineState(forStageAt index: Int) -> BillTimelineStageState {
        let stage = bill.stages[index]
        if stage.isCompleted {
            return .completed
        }

        let firstIncompleteIndex = bill.stages.firstIndex { !$0.isCompleted }
        return index == firstIncompleteIndex ? .current : .future
    }

    // MARK: - Cross-reference loading

    @MainActor
    private func loadCrossReferences() async {
        let billNumber = bill.number

        // Votes: match by billNumberCode field
        let allVotes = (try? modelContext.fetch(FetchDescriptor<RecordedVote>())) ?? []
        matchingVotes = allVotes.filter {
            !$0.billNumberCode.isEmpty &&
            $0.billNumberCode.localizedCaseInsensitiveContains(billNumber)
        }

        // Debates: match by subject title
        let allSubjects = (try? modelContext.fetch(FetchDescriptor<SubjectOfBusiness>())) ?? []
        matchingDebates = allSubjects.filter {
            $0.title.localizedCaseInsensitiveContains(billNumber)
        }

        // Resolve members once for myMP, sponsorMember, and amendment mover matching
        let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
        memberRoster = allMembers
        if let name = PostalCodeViewModel.savedMemberName {
            myMP = allMembers.first(where: {
                $0.name.localizedCaseInsensitiveContains(name) ||
                name.localizedCaseInsensitiveContains($0.lastName)
            })
        }
        // Sponsor party: match bill.sponsorName against member list for party badge
        if !bill.sponsorName.isEmpty {
            let parts = bill.sponsorName.components(separatedBy: " ")
            let lastName = parts.last ?? ""
            sponsorMember = allMembers.first(where: {
                $0.lastName.localizedCaseInsensitiveCompare(lastName) == .orderedSame &&
                bill.sponsorName.localizedCaseInsensitiveContains($0.firstName.prefix(BillDetailLayout.sponsorMatchPrefixLength))
            })
        }
    }

    @MainActor
    private func loadLobbyingContext() async {
        guard autoloadLobbyingContext else { return }

        do {
            let context = try await loadBillLobbyingContext.execute(billID: bill.id)
            lobbyingContext = context.hasCommunications ? context : nil
        } catch {
            lobbyingContext = nil
        }
    }

    @MainActor
    private func loadCommitteeStage() async {
        guard autoloadCommitteeStage else { return }

        do {
            committeeStage = try await loadBillCommitteeStage.execute(billID: bill.id)
        } catch {
            committeeStage = nil
        }
    }

    @MainActor
    private func loadAmendments() async {
        guard autoloadAmendments else { return }

        do {
            amendments = try await loadBillAmendments.execute(billID: bill.id)
        } catch {
            amendments = []
        }
        amendmentsLoaded = true
    }
}

private enum BillTimelineStageState: Equatable {
    case completed
    case current
    case future

    var systemImage: String {
        switch self {
        case .completed:
            return "checkmark.circle.fill"
        case .current:
            return "circle.circle.fill"
        case .future:
            return "circle.dotted"
        }
    }

    var color: Color {
        switch self {
        case .completed:
            return .appPositive
        case .current:
            return .accentColor
        case .future:
            return .appNeutral
        }
    }

    var accessibilityStatus: String {
        switch self {
        case .completed:
            return NSLocalizedString("bills.timeline.completed", comment: "")
        case .current:
            return NSLocalizedString("bills.timeline.current", comment: "")
        case .future:
            return NSLocalizedString("bills.timeline.future", comment: "")
        }
    }

    var displayName: String {
        accessibilityStatus
    }
}

private struct BillHeaderBadge: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, BillDetailLayout.badgeHorizontalPadding)
            .padding(.vertical, BillDetailLayout.badgeVerticalPadding)
            .background(background, in: Capsule())
    }
}
