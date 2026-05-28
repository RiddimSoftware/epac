//
//  MemberVotingHistoryView.swift
//  epac
//
//  Created by Codex on 2026-04-27.
//

import SwiftData
import SwiftUI

private enum Layout {
    static let retryDelaySeconds = 2
    static let retryDelay: Duration = .seconds(retryDelaySeconds)
    static let rowSpacing: CGFloat = 12
    static let rowTextSpacing: CGFloat = 3
    static let rowLineLimit = 2
    static let badgeHorizontalPadding: CGFloat = 6
    static let badgeVerticalPadding: CGFloat = 3
    static let badgeMinWidth: CGFloat = 44
}

private struct VoteSelection: Identifiable, Hashable {
    let id = UUID()
    let mv: MemberVote
    let rv: RecordedVote?

    static func == (lhs: VoteSelection, rhs: VoteSelection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MemberVotingHistoryView: View {
    let member: ParliamentMember

    @EnvironmentObject private var fetch: Fetch
    @Environment(\.modelContext) private var modelContext
    @State private var votes: [(mv: MemberVote, rv: RecordedVote?)] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var isRetryDisabled = false
    @State private var selectedVote: VoteSelection?

    var body: some View {
        Group {
            if isLoading && votes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed && votes.isEmpty {
                ContentUnavailableView {
                    Label(NSLocalizedString("votes.error.title", comment: ""), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(NSLocalizedString("votes.error.description", comment: ""))
                } actions: {
                    Button(NSLocalizedString("votes.error.retry", comment: "")) {
                        guard !isRetryDisabled else { return }
                        isRetryDisabled = true
                        Task { try? await Task.sleep(for: Layout.retryDelay); isRetryDisabled = false }
                        Task { await loadVotes() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetryDisabled)
                }
            } else if votes.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("votes.empty.title", comment: ""),
                    systemImage: "hand.raised.slash",
                    description: Text(NSLocalizedString("votes.empty.description", comment: ""))
                )
            } else {
                List {
                    ForEach(Array(votes.enumerated()), id: \.offset) { index, pair in
                        Button {
                            selectedVote = VoteSelection(mv: pair.mv, rv: pair.rv)
                        } label: {
                            VoteRow(mv: pair.mv, rv: pair.rv)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier(index == 0 ? "vote-list-row-0" : "vote-list-row-\(index)")
                    }
                    Section {
                        HStack {
                            Spacer()
                            DataSourceBadge(source: .votes())
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .adaptiveReadingWidth()
                .accessibilityIdentifier("vote-detail-mp-list")
                .refreshable {
                    await loadVotes(forceRefresh: true)
                }
                .navigationDestination(item: $selectedVote) { selection in
                    VoteDetailView(mv: selection.mv, rv: selection.rv)
                        .environmentObject(fetch)
                }
            }
        }
        .navigationTitle(NSLocalizedString("votes.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: member.memberID) {
            await loadVotes()
        }
    }

    @MainActor
    private func loadVotes(forceRefresh: Bool = false) async {
        isLoading = true
        loadFailed = false
        let mid = member.memberID
        do {
            if forceRefresh {
                try await fetch.refreshMemberVotes(memberID: mid)
            } else {
                try await fetch.downloadMemberVotes(memberID: mid)
            }
        } catch {
            loadFailed = true
        }
        let mvs = (try? modelContext.fetch(FetchDescriptor<MemberVote>(
            predicate: #Predicate { $0.memberID == mid }
        ))) ?? []
        votes = mvs
            .sorted { $0.voteID > $1.voteID }
            .map { mv in (mv: mv, rv: mv.vote) }
        isLoading = false
    }
}

private struct VoteRow: View {
    let mv: MemberVote
    let rv: RecordedVote?

    var body: some View {
        HStack(alignment: .top, spacing: Layout.rowSpacing) {
            ballotBadge
            VStack(alignment: .leading, spacing: Layout.rowTextSpacing) {
                if let bill = rv?.billNumberCode, !bill.isEmpty {
                    Text(bill).font(.caption).foregroundStyle(.secondary)
                }
                Text(rv?.descriptionEn ?? "Vote #\(mv.voteID)")
                    .font(.subheadline)
                    .lineLimit(Layout.rowLineLimit)
                if let date = rv?.date {
                    Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, EpacSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var ballotBadge: some View {
        Text(mv.recordedVote)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Layout.badgeHorizontalPadding).padding(.vertical, Layout.badgeVerticalPadding)
            .background(badgeColor)
            .clipShape(Capsule())
            .frame(minWidth: Layout.badgeMinWidth)
    }

    private var badgeColor: Color {
        Color.ballot(mv.recordedVote)
    }
}
