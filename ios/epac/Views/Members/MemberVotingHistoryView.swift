//
//  MemberVotingHistoryView.swift
//  epac
//
//  Created by Codex on 2026-04-27.
//

import SwiftUI
import SwiftData

struct MemberVotingHistoryView: View {
    let member: ParliamentMember

    @EnvironmentObject private var fetch: Fetch
    @Environment(\.modelContext) private var modelContext
    @State private var votes: [(mv: MemberVote, rv: RecordedVote?)] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && votes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if votes.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("votes.empty.title", comment: ""),
                    systemImage: "hand.raised.slash",
                    description: Text(NSLocalizedString("votes.empty.description", comment: ""))
                )
            } else {
                List(votes, id: \.mv.voteID) { pair in
                    VoteRow(mv: pair.mv, rv: pair.rv)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("votes.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: member.memberID) {
            isLoading = true
            let mid = member.memberID
            try? await fetch.downloadMemberVotes(memberID: mid)
            let mvs = (try? modelContext.fetch(FetchDescriptor<MemberVote>(
                predicate: #Predicate { $0.memberID == mid }
            ))) ?? []
            votes = mvs
                .sorted { $0.voteID > $1.voteID }
                .map { mv in (mv: mv, rv: mv.vote) }
            isLoading = false
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
        switch mv.recordedVote.lowercased() {
        case "yea":    return .green
        case "nay":    return .red
        case "paired": return .orange
        default:       return Color(.systemGray3)
        }
    }
}
