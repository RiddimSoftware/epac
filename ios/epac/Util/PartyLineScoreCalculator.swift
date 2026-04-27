//
//  PartyLineScoreCalculator.swift
//  epac
//

import Foundation

struct PartyLineScoreResult {
    let score: Double          // 0.0–1.0
    let totalVotes: Int        // denominator (Yea+Nay only)
    let withPartyCount: Int    // numerator
}

struct PartyLineScoreCalculator {
    /// Computes how often `memberID` voted with the majority of same-party members.
    /// - Parameters:
    ///   - memberVotes: all MemberVote rows for the target member (any ballot type)
    ///   - allVotesByID: dictionary mapping voteID → [MemberVote] for ALL members on that vote
    ///   - partyForMemberID: closure that returns the Party for a given memberID (nil if unknown)
    ///   - memberParty: the target member's own Party
    /// - Returns: nil if there are no qualifying votes
    static func compute(
        memberVotes: [MemberVote],
        allVotesByID: [Int: [MemberVote]],
        partyForMemberID: (Int) -> Party?,
        memberParty: Party
    ) -> PartyLineScoreResult? {
        var total = 0
        var withParty = 0

        for mv in memberVotes {
            let ballot = mv.recordedVote.lowercased()
            guard ballot == "yea" || ballot == "nay" else { continue }
            total += 1

            let coPartyVotes = (allVotesByID[mv.voteID] ?? []).filter {
                $0.memberID != mv.memberID &&
                partyForMemberID($0.memberID) == memberParty &&
                ($0.recordedVote.lowercased() == "yea" || $0.recordedVote.lowercased() == "nay")
            }
            guard !coPartyVotes.isEmpty else { continue }
            let yeaCount = coPartyVotes.filter { $0.recordedVote.lowercased() == "yea" }.count
            let partyMajority = yeaCount >= coPartyVotes.count - yeaCount ? "yea" : "nay"
            if ballot == partyMajority { withParty += 1 }
        }

        guard total > 0 else { return nil }
        return PartyLineScoreResult(score: Double(withParty) / Double(total),
                                    totalVotes: total,
                                    withPartyCount: withParty)
    }
}
