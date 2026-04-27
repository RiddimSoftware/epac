//
//  TorontoVotesView.swift
//  epac
//
//  Browsable list of Toronto City Council votes, filterable by topic category.
//

import SwiftUI

struct TorontoVotesView: View {
    @State private var votes: [TorontoCouncilVote] = []
    @State private var selectedCategory: TorontoCouncilVote.VoteCategory?
    @State private var isLoading = false

    private var filteredVotes: [TorontoCouncilVote] {
        guard let category = selectedCategory else { return votes }
        return votes.filter { $0.category == category }
    }

    private var groupedVotes: [(key: String, votes: [TorontoCouncilVote])] {
        let grouped = Dictionary(grouping: filteredVotes) { vote in
            "\(vote.agendaItemNumber)-\(vote.voteDescription)"
        }
        let latestDate = grouped.mapValues { votes in
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
                    title: NSLocalizedString("toronto.votes.empty.title", comment: ""),
                    message: NSLocalizedString("toronto.votes.empty.description", comment: ""),
                    action: nil
                )
            } else {
                votesList
            }
        }
        .navigationTitle(NSLocalizedString("toronto.votes.navTitle", comment: ""))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(NSLocalizedString("toronto.votes.allCategories", comment: "")) {
                        selectedCategory = nil
                    }
                    Divider()
                    ForEach(TorontoCouncilVote.VoteCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) { selectedCategory = category }
                    }
                } label: {
                    Label(selectedCategory?.rawValue ?? NSLocalizedString("toronto.votes.filter", comment: ""),
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
                VoteGroupRow(votes: group.votes)
            }
            Section {
                Link(NSLocalizedString("toronto.votes.sourceLink", comment: ""),
                     destination: URL(string: "https://open.toronto.ca/dataset/members-of-toronto-city-council-voting-record/")!)
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
        votes = await TorontoCouncilService.fetchRecentVotes()
    }
}

private struct VoteGroupRow: View {
    let votes: [TorontoCouncilVote]

    private var firstVote: TorontoCouncilVote? { votes.first }

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
                .padding(.vertical, 2)
                .accessibilityLabel("\(vote.councillorName): \(vote.voteDetail)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(firstVote?.agendaItemTitle ?? "")
                    .font(.subheadline)
                    .lineLimit(2)
                if let description = firstVote?.voteDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let itemNumber = firstVote?.agendaItemNumber, !itemNumber.isEmpty {
                        Text(itemNumber)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let date = firstVote?.date, date > Date.distantPast {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let category = firstVote?.category {
                        Text(category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func voteColor(_ detail: String) -> Color {
        switch detail.lowercased() {
        case "yes": return .green
        case "no": return .red
        case "conflict": return .orange
        default: return .secondary
        }
    }
}
