//
//  VancouverVotesView.swift
//  epac
//
//  Browsable list of Vancouver City Council votes, filterable by topic category.
//

import SwiftUI

private enum Layout {
    static let groupTitleSpacing: CGFloat = 3
    static let titleLineLimit = 2
    static let badgeHorizontalPadding: CGFloat = 6
}

struct VancouverVotesView: View {
    @State private var votes: [VancouverCouncilVote] = []
    @State private var selectedCategory: VancouverCouncilVote.VoteCategory?
    @State private var isLoading = false

    private var filteredVotes: [VancouverCouncilVote] {
        guard let category = selectedCategory else { return votes }
        return votes.filter { $0.category == category }
    }

    private var groupedVotes: [(key: String, votes: [VancouverCouncilVote])] {
        let grouped = Dictionary(grouping: filteredVotes) { $0.voteNumber }
        // Build a date-lookup dict so the sort is O(n log n) rather than O(n^2).
        let latestDate: [String: Date] = grouped.mapValues { votes in
            votes.map(\.date).max() ?? .distantPast
        }
        return grouped
            .sorted { latestDate[$0.key, default: .distantPast] > latestDate[$1.key, default: .distantPast] }
            .map { (key: $0.key, votes: $0.value) }
    }

    var body: some View {
        Group {
            if isLoading && votes.isEmpty {
                ProgressView()
            } else if filteredVotes.isEmpty {
                EmptyStateView(
                    icon: "building.2",
                    title: NSLocalizedString("vancouver.votes.empty.title", comment: ""),
                    message: NSLocalizedString("vancouver.votes.empty.description", comment: ""),
                    action: nil
                )
            } else {
                votesList
            }
        }
        .navigationTitle(NSLocalizedString("vancouver.votes.navTitle", comment: ""))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(NSLocalizedString("vancouver.votes.allCategories", comment: "")) {
                        selectedCategory = nil
                    }
                    Divider()
                    ForEach(VancouverCouncilVote.VoteCategory.allCases, id: \.self) { cat in
                        Button(cat.rawValue) { selectedCategory = cat }
                    }
                } label: {
                    Label(selectedCategory?.rawValue ?? NSLocalizedString("vancouver.votes.filter", comment: ""),
                          systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await load() }
    }

    private var votesList: some View {
        List {
            if let category = selectedCategory {
                Section {
                    Text(category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(groupedVotes, id: \.key) { group in
                VoteGroupRow(voteNumber: group.key, votes: group.votes)
            }
            Section {
                Link(NSLocalizedString("vancouver.votes.sourceLink", comment: ""),
                     // swiftlint:disable:next force_unwrapping
                     destination: URL(string: "https://opendata.vancouver.ca/explore/dataset/council-voting-records")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        votes = await VancouverCouncilService.fetchRecentVotes()
    }
}

// MARK: - Vote group row

private struct VoteGroupRow: View {
    let voteNumber: String
    let votes: [VancouverCouncilVote]

    private var firstVote: VancouverCouncilVote? { votes.first }

    var body: some View {
        DisclosureGroup {
            ForEach(votes) { vote in
                HStack {
                    Text(vote.councillorName)
                        .font(.subheadline)
                    Spacer()
                    Text(vote.voteDetail)
                        .font(.caption)
                        .foregroundStyle(voteColor(vote.voteDetail))
                        .fontWeight(.medium)
                }
                .padding(.vertical, EpacSpacing.xxs)
                .accessibilityLabel("\(vote.councillorName): \(vote.voteDetail)")
            }
        } label: {
            VStack(alignment: .leading, spacing: Layout.groupTitleSpacing) {
                Text(firstVote?.motionTitle ?? voteNumber)
                    .font(.subheadline)
                    .lineLimit(Layout.titleLineLimit)
                HStack(spacing: EpacSpacing.s) {
                    if let date = firstVote?.date, date > Date.distantPast {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let cat = firstVote?.category {
                        Text(cat.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Layout.badgeHorizontalPadding)
                            .padding(.vertical, EpacSpacing.xxs)
                            .background(Color.secondary.opacity(EpacOpacity.tint))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, EpacSpacing.xs)
        }
    }

    private func voteColor(_ detail: String) -> Color {
        switch detail.lowercased() {
        case "in favour": return .green
        case "opposed":   return .red
        default:          return .secondary
        }
    }
}
