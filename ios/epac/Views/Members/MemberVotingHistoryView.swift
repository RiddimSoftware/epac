//
//  MemberVotingHistoryView.swift
//  epac
//
//  Created by Codex on 2026-04-27.
//

import SwiftUI
import SwiftData

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
                        Task { try? await Task.sleep(for: .seconds(2)); isRetryDisabled = false }
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
                    ForEach(votes, id: \.mv.voteID) { pair in
                        Button {
                            selectedVote = VoteSelection(mv: pair.mv, rv: pair.rv)
                        } label: {
                            VoteRow(mv: pair.mv, rv: pair.rv)
                        }
                        .foregroundStyle(.primary)
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
        let countBefore = (try? modelContext.fetchCount(FetchDescriptor<MemberVote>(
            predicate: #Predicate { $0.memberID == mid }
        ))) ?? 0
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

        // Notify if new votes arrived and this member is followed.
        // Only fires on the first sync (countBefore == 0) to avoid
        // spamming notifications on every profile open.
        if countBefore == 0, !votes.isEmpty,
           MemberFollowStore.shared.isFollowing(mid),
           let newest = votes.first {
            let desc = newest.rv?.descriptionEn ?? "Vote #\(newest.mv.voteID)"
            MemberNotificationScheduler.scheduleVoteNotification(
                memberName: member.name,
                ballot: newest.mv.recordedVote,
                description: desc,
                memberID: mid
            )
        }
    }
}

private struct VoteRow: View {
    let mv: MemberVote
    let rv: RecordedVote?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ballotBadge
            VStack(alignment: .leading, spacing: 3) {
                if let bill = rv?.billNumberCode, !bill.isEmpty {
                    Text(bill).font(.caption).foregroundStyle(.secondary)
                }
                Text(rv?.descriptionEn ?? "Vote #\(mv.voteID)")
                    .font(.subheadline)
                    .lineLimit(2)
                if let date = rv?.date {
                    Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var ballotBadge: some View {
        Text(mv.recordedVote)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(badgeColor)
            .clipShape(Capsule())
            .frame(minWidth: 44)
    }

    private var badgeColor: Color {
        Color.ballot(mv.recordedVote)
    }
}
