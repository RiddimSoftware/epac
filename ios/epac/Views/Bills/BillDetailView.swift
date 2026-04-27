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

    var body: some View {
        List {
            // MARK: Summary
            Section {
                LabeledContent(
                    NSLocalizedString("bills.detail.number", comment: ""),
                    value: bill.number
                )
                LabeledContent(
                    NSLocalizedString("bills.detail.status", comment: ""),
                    value: bill.status.displayName
                )
                if !bill.sponsorName.isEmpty {
                    LabeledContent(
                        NSLocalizedString("bills.detail.sponsor", comment: ""),
                        value: bill.sponsorName
                    )
                }
                if !bill.currentStage.isEmpty {
                    LabeledContent(
                        NSLocalizedString("bills.detail.stage", comment: ""),
                        value: bill.currentStage
                    )
                }
                if let introduced = bill.introducedDate {
                    LabeledContent(
                        NSLocalizedString("bills.detail.introduced", comment: ""),
                        value: introduced.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if !bill.billType.displayName.isEmpty {
                    LabeledContent(
                        NSLocalizedString("bills.detail.type", comment: ""),
                        value: bill.billType.displayName
                    )
                }
            }

            // MARK: PBO independent cost analysis
            PBOCostCard(bill: bill)

            // MARK: Stage timeline
            Section(NSLocalizedString("bills.detail.timeline", comment: "")) {
                ForEach(bill.stages) { stage in
                    HStack(spacing: 12) {
                        Image(systemName: stage.isCompleted
                              ? "checkmark.circle.fill"
                              : "circle.dotted")
                            .foregroundStyle(stage.isCompleted
                                ? Color.appPositive
                                : Color.appNeutral)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage.name).font(.subheadline)
                            if let date = stage.completedDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
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

        // My MP: resolve from postal code for Contact button
        if let name = PostalCodeViewModel.savedMemberName {
            let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
            myMP = allMembers.first(where: {
                $0.name.localizedCaseInsensitiveContains(name) ||
                name.localizedCaseInsensitiveContains($0.lastName)
            })
        }
    }
}
