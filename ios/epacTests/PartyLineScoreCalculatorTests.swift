@testable import epac
import Foundation
import Testing

struct PartyLineScoreCalculatorTests {

    // MARK: - Helpers

    private func vote(voteID: Int, memberID: Int, ballot: String) -> MemberVote {
        MemberVote(voteID: voteID, memberID: memberID, recordedVote: ballot)
    }

    // MARK: - Returns nil when no qualifying votes

    @Test func returnsNilWhenMemberHasNoVotes() {
        let result = PartyLineScoreCalculator.compute(
            memberVotes: [],
            allVotesByID: [:],
            partyForMemberID: { _ in .liberal },
            memberParty: .liberal
        )
        #expect(result == nil)
    }

    @Test func returnsNilWhenAllVotesArePaired() {
        let mv = vote(voteID: 1, memberID: 10, ballot: "Paired")
        let result = PartyLineScoreCalculator.compute(
            memberVotes: [mv],
            allVotesByID: [1: [mv]],
            partyForMemberID: { _ in .liberal },
            memberParty: .liberal
        )
        #expect(result == nil)
    }

    @Test func returnsNilWhenAllVotesAreAbstained() {
        let mv = vote(voteID: 1, memberID: 10, ballot: "Abstained")
        let result = PartyLineScoreCalculator.compute(
            memberVotes: [mv],
            allVotesByID: [1: [mv]],
            partyForMemberID: { _ in .liberal },
            memberParty: .liberal
        )
        #expect(result == nil)
    }

    @Test func pairedAndAbstainedVotesAreExcludedFromDenominator() {
        let myVotes = [
            vote(voteID: 1, memberID: 10, ballot: "Yea"),
            vote(voteID: 2, memberID: 10, ballot: "Paired"),
            vote(voteID: 3, memberID: 10, ballot: "Abstained")
        ]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Yea"),
                vote(voteID: 1, memberID: 11, ballot: "Yea")],
            2: [vote(voteID: 2, memberID: 10, ballot: "Paired"),
                vote(voteID: 2, memberID: 11, ballot: "Yea")],
            3: [vote(voteID: 3, memberID: 10, ballot: "Abstained"),
                vote(voteID: 3, memberID: 11, ballot: "Nay")]
        ]
        let partyMap: [Int: Party] = [10: .liberal, 11: .liberal]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .liberal
        )

        #expect(result?.totalVotes == 1)
        #expect(result?.withPartyCount == 1)
        #expect(result?.score == 1.0)
    }

    // MARK: - Score computation

    @Test func perfectPartyLinePerfectScore() {
        // Member 10 votes Yea on votes 1 and 2.
        // Co-party members also vote Yea on both → score = 1.0
        let myVotes = [
            vote(voteID: 1, memberID: 10, ballot: "Yea"),
            vote(voteID: 2, memberID: 10, ballot: "Yea")
        ]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Yea"),
                vote(voteID: 1, memberID: 11, ballot: "Yea"),
                vote(voteID: 1, memberID: 12, ballot: "Yea")],
            2: [vote(voteID: 2, memberID: 10, ballot: "Yea"),
                vote(voteID: 2, memberID: 11, ballot: "Yea"),
                vote(voteID: 2, memberID: 12, ballot: "Yea")]
        ]
        let partyMap: [Int: Party] = [10: .liberal, 11: .liberal, 12: .liberal]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .liberal
        )
        #expect(result != nil)
        #expect(result?.score == 1.0)
        #expect(result?.totalVotes == 2)
        #expect(result?.withPartyCount == 2)
    }

    @Test func zeroPartyLineScore() {
        // Member 10 votes Yea; co-party votes Nay (majority Nay) → 0 with party
        let myVotes = [vote(voteID: 1, memberID: 10, ballot: "Yea")]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Yea"),
                vote(voteID: 1, memberID: 11, ballot: "Nay"),
                vote(voteID: 1, memberID: 12, ballot: "Nay")]
        ]
        let partyMap: [Int: Party] = [10: .conservative, 11: .conservative, 12: .conservative]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .conservative
        )
        #expect(result != nil)
        #expect(result?.score == 0.0)
        #expect(result?.totalVotes == 1)
        #expect(result?.withPartyCount == 0)
    }

    @Test func partialScore() {
        // 4 votes: member with party on 3, against on 1 → 0.75
        let myVotes = [
            vote(voteID: 1, memberID: 10, ballot: "Yea"),  // with party (party = Yea)
            vote(voteID: 2, memberID: 10, ballot: "Yea"),  // with party (party = Yea)
            vote(voteID: 3, memberID: 10, ballot: "Nay"),  // with party (party = Nay)
            vote(voteID: 4, memberID: 10, ballot: "Yea")   // against party (party = Nay)
        ]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Yea"),
                vote(voteID: 1, memberID: 11, ballot: "Yea")],
            2: [vote(voteID: 2, memberID: 10, ballot: "Yea"),
                vote(voteID: 2, memberID: 11, ballot: "Yea")],
            3: [vote(voteID: 3, memberID: 10, ballot: "Nay"),
                vote(voteID: 3, memberID: 11, ballot: "Nay")],
            4: [vote(voteID: 4, memberID: 10, ballot: "Yea"),
                vote(voteID: 4, memberID: 11, ballot: "Nay")]
        ]
        let partyMap: [Int: Party] = [10: .newdemocratic, 11: .newdemocratic]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .newdemocratic
        )
        #expect(result != nil)
        #expect(result?.totalVotes == 4)
        #expect(result?.withPartyCount == 3)
        #expect(result?.score == 0.75)
    }

    // MARK: - Cross-party votes are excluded from co-party lookup

    @Test func oppositionVotesDoNotInfluencePartyMajority() {
        // Member 10 is Liberal, votes Nay.
        // Co-party (Liberal 11) votes Yea, opposition (Conservative 20) votes Nay.
        // Party majority should be determined only by Liberal members → Yea.
        // Member 10 voted Nay → against party → score = 0.
        let myVotes = [vote(voteID: 1, memberID: 10, ballot: "Nay")]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Nay"),
                vote(voteID: 1, memberID: 11, ballot: "Yea"),
                vote(voteID: 1, memberID: 20, ballot: "Nay")]
        ]
        let partyMap: [Int: Party] = [10: .liberal, 11: .liberal, 20: .conservative]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .liberal
        )
        #expect(result?.score == 0.0)
        #expect(result?.withPartyCount == 0)
    }

    @Test func nayOnlyVotesCanProducePerfectScore() {
        let myVotes = [
            vote(voteID: 1, memberID: 10, ballot: "Nay"),
            vote(voteID: 2, memberID: 10, ballot: "Nay")
        ]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Nay"),
                vote(voteID: 1, memberID: 11, ballot: "Nay"),
                vote(voteID: 1, memberID: 12, ballot: "Yea"),
                vote(voteID: 1, memberID: 13, ballot: "Nay")],
            2: [vote(voteID: 2, memberID: 10, ballot: "Nay"),
                vote(voteID: 2, memberID: 11, ballot: "Nay"),
                vote(voteID: 2, memberID: 12, ballot: "Nay")]
        ]
        let partyMap: [Int: Party] = [10: .conservative, 11: .conservative, 12: .conservative, 13: .conservative]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .conservative
        )

        #expect(result?.score == 1.0)
        #expect(result?.totalVotes == 2)
        #expect(result?.withPartyCount == 2)
    }

    // MARK: - Votes skipped when no co-party members voted

    @Test func voteWithNoCoPartyMembersIsSkippedInNumeratorButCountedInTotal() {
        // Member 10 votes Yea on voteID=1, but no co-party members have any rows for that vote.
        let myVotes = [vote(voteID: 1, memberID: 10, ballot: "Yea")]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Yea")]  // only the member themselves
        ]
        let partyMap: [Int: Party] = [10: .bloc]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .bloc
        )
        // total increments to 1 for the Yea, but coPartyVotes is empty → continue skips withParty increment.
        // However total is still 1 (incremented before the guard), so result is non-nil with score=0.
        #expect(result != nil)
        #expect(result?.totalVotes == 1)
        #expect(result?.withPartyCount == 0)
        #expect(result?.score == 0.0)
    }

    @Test func independentMemberWithoutCaucusScoresZeroForQualifyingVotes() {
        let myVotes = [
            vote(voteID: 1, memberID: 10, ballot: "Yea"),
            vote(voteID: 2, memberID: 10, ballot: "Nay")
        ]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "Yea"),
                vote(voteID: 1, memberID: 20, ballot: "Yea")],
            2: [vote(voteID: 2, memberID: 10, ballot: "Nay"),
                vote(voteID: 2, memberID: 20, ballot: "Nay")]
        ]
        let partyMap: [Int: Party] = [10: .independent, 20: .liberal]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .independent
        )

        #expect(result?.score == 0.0)
        #expect(result?.totalVotes == 2)
        #expect(result?.withPartyCount == 0)
    }

    // MARK: - recordedVote case insensitivity

    @Test func recordedVoteCaseInsensitive() {
        // Mix of "YEA", "Yea", "yea" should all be treated equivalently
        let myVotes = [vote(voteID: 1, memberID: 10, ballot: "YEA")]
        let allByVoteID: [Int: [MemberVote]] = [
            1: [vote(voteID: 1, memberID: 10, ballot: "YEA"),
                vote(voteID: 1, memberID: 11, ballot: "Yea")]
        ]
        let partyMap: [Int: Party] = [10: .green, 11: .green]

        let result = PartyLineScoreCalculator.compute(
            memberVotes: myVotes,
            allVotesByID: allByVoteID,
            partyForMemberID: { partyMap[$0] },
            memberParty: .green
        )
        #expect(result?.score == 1.0)
    }
}
