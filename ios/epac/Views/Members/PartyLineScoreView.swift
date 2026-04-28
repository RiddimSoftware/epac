//
//  PartyLineScoreView.swift
//  epac
//

import SwiftData
import SwiftUI

struct PartyLineScoreView: View {
    let member: ParliamentMember
    @Environment(\.modelContext) private var modelContext
    @State private var result: PartyLineScoreResult?
    @State private var showInfo = false

    var body: some View {
        Group {
            if let result {
                scoreCard(result)
            }
        }
        .task(id: member.memberID) { await computeScore() }
    }

    private func scoreCard(_ result: PartyLineScoreResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("partyLine.title", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(NSLocalizedString("partyLine.infoButton", comment: ""))
            }
            Text(String(format: NSLocalizedString("partyLine.score", comment: ""), Int(result.score * 100)))
                .font(.title2.weight(.semibold))
            ProgressView(value: result.score)
                .tint(Color.party(member.party))
                .accessibilityLabel(NSLocalizedString("partyLine.title", comment: ""))
                .accessibilityValue(String(format: "%.0f%%", result.score * 100))
            Text(String(format: NSLocalizedString("partyLine.denominator", comment: ""),
                        result.withPartyCount, result.totalVotes))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showInfo) { infoSheet }
    }

    private var infoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(NSLocalizedString("partyLine.info.body", comment: ""))
                        .font(.body)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("partyLine.info.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("partyLine.info.done", comment: "")) {
                        showInfo = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func computeScore() async {
        result = nil
        let mid = member.memberID
        let party = member.party

        // Fetch this member's votes
        guard let myVotes = try? modelContext.fetch(FetchDescriptor<MemberVote>(
            predicate: #Predicate { $0.memberID == mid }
        )), !myVotes.isEmpty else { return }

        // Gather unique voteIDs where member voted Yea/Nay
        let voteIDs = Set(myVotes.filter {
            let b = $0.recordedVote.lowercased()
            return b == "yea" || b == "nay"
        }.map(\.voteID))

        // Fetch all MemberVote rows for those voteIDs (may include other members)
        var allByVoteID: [Int: [MemberVote]] = [:]
        for vid in voteIDs {
            let rows = (try? modelContext.fetch(FetchDescriptor<MemberVote>(
                predicate: #Predicate { $0.voteID == vid }
            ))) ?? []
            allByVoteID[vid] = rows
        }

        // Build party lookup from ParliamentMember
        let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
        let partyMap = Dictionary(uniqueKeysWithValues: allMembers.compactMap { m -> (Int, Party)? in
            guard m.memberID > 0 else { return nil }
            return (m.memberID, m.party)
        })

        result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: party
        )
    }
}
