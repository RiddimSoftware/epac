//
//  BillDetailView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI
import SwiftData
import ActivityView

struct BillDetailView: View {
    let bill: Bill
    @Environment(\.modelContext) private var modelContext

    @State private var billStore = BillFollowStore.shared
    @State private var matchingVotes: [RecordedVote] = []
    @State private var matchingDebates: [SubjectOfBusiness] = []
    @State private var shareItem: ActivityItem?
    @State private var myMP: ParliamentMember?
    @State private var sponsorMember: ParliamentMember?

    var body: some View {
        List {
            billHeaderSection
            keyFactsSection

            // MARK: PBO independent cost analysis
            PBOCostCard(bill: bill)

            // MARK: Stage timeline
            Section(NSLocalizedString("bills.detail.timeline", comment: "")) {
                ForEach(Array(bill.stages.enumerated()), id: \.element.id) { index, stage in
                    let state = timelineState(forStageAt: index)
                    HStack(spacing: 12) {
                        Image(systemName: state.systemImage)
                            .foregroundStyle(state.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vote.descriptionEn)
                                .font(.subheadline)
                                .lineLimit(2)
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
                            .lineLimit(2)
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
        .task { await loadCrossReferences() }
        .activitySheet($shareItem)
    }

    private var billHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bill.number)
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Spacer(minLength: 8)
                    if !bill.billType.shortName.isEmpty {
                        BillHeaderBadge(
                            text: bill.billType.shortName,
                            foreground: .white,
                            background: Color.accentColor.opacity(0.85)
                        )
                    }
                    BillHeaderBadge(
                        text: bill.status.displayName,
                        foreground: .white,
                        background: bill.status.color
                    )
                }

                Text(bill.title)
                    .font(.headline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !bill.currentStage.isEmpty {
                    Text(bill.currentStage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .explainerTip(for: bill.currentStage)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel)
        }
    }

    private var keyFactsSection: some View {
        Section(NSLocalizedString("bills.detail.keyFacts", comment: "")) {
            if !bill.sponsorName.isEmpty {
                LabeledContent(NSLocalizedString("bills.detail.sponsor", comment: "")) {
                    HStack(spacing: 6) {
                        Text(bill.sponsorName)
                        if let party = sponsorMember?.party {
                            PartyBadge(party: party)
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
            if !bill.billType.displayName.isEmpty {
                LabeledContent(NSLocalizedString("bills.detail.type", comment: "")) {
                    Text(bill.billType.displayName)
                        .explainerTip(for: bill.billType.displayName)
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

    private var originatingChamberName: String? {
        switch bill.billType {
        case .houseGovernment, .privateMember:
            return NSLocalizedString("bills.chamber.house", comment: "")
        case .senateGovernment, .senatePublic, .senatePrivate:
            return NSLocalizedString("bills.chamber.senate", comment: "")
        case .unknown:
            return nil
        }
    }

    private var headerAccessibilityLabel: String {
        [
            bill.number,
            bill.title,
            bill.status.displayName,
            bill.billType.displayName,
            bill.currentStage,
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

        // Resolve members once for both myMP and sponsorMember
        let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
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
                bill.sponsorName.localizedCaseInsensitiveContains($0.firstName.prefix(3))
            })
        }
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}
