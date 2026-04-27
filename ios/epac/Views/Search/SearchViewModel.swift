//
//  SearchViewModel.swift
//  epac
//

import Foundation
import Observation

// Filters cached parliamentary data across four corpora: MPs, votes, bills, debate subjects.
// Results per section are capped to keep SwiftUI responsive on large datasets.
@MainActor
@Observable
class SearchViewModel {
    var searchText = ""

    private static let maxPerSection = 50

    // MARK: - Result types

    struct MemberResult: Identifiable {
        let id: Int  // memberID
        let member: ParliamentMember
    }

    struct VoteResult: Identifiable {
        let id: Int  // voteID
        let vote: RecordedVote
    }

    struct DebateResult: Identifiable {
        let id: String  // subject hansardID
        let hansardDate: Date
        let subject: SubjectOfBusiness
        let hansard: Hansard
    }

    struct SearchResults {
        var members: [MemberResult] = []
        var votes: [VoteResult] = []
        var debates: [DebateResult] = []

        var isEmpty: Bool { members.isEmpty && votes.isEmpty && debates.isEmpty }
    }

    var isQueryTooShort: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
    }

    func results(
        members: [ParliamentMember],
        votes: [RecordedVote],
        hansards: [Hansard]
    ) -> SearchResults {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return SearchResults() }

        var out = SearchResults()

        // Members: match name, riding, party full name
        for member in members {
            if member.name.localizedCaseInsensitiveContains(q)
                || member.riding.localizedCaseInsensitiveContains(q)
                || member.party.fullName.localizedCaseInsensitiveContains(q) {
                out.members.append(MemberResult(id: member.memberID, member: member))
                if out.members.count >= Self.maxPerSection { break }
            }
        }

        // Votes: match description, bill number
        for vote in votes {
            if vote.descriptionEn.localizedCaseInsensitiveContains(q)
                || vote.billNumberCode.localizedCaseInsensitiveContains(q) {
                out.votes.append(VoteResult(id: vote.voteID, vote: vote))
                if out.votes.count >= Self.maxPerSection { break }
            }
        }

        // Debates: match subject title (hansards arrive sorted newest-first)
        outer: for hansard in hansards {
            for order in hansard.orders {
                for subject in order.subjects where !subject.speeches.isEmpty {
                    if subject.title.localizedCaseInsensitiveContains(q) {
                        out.debates.append(DebateResult(
                            id: subject.hansardID,
                            hansardDate: hansard.date,
                            subject: subject,
                            hansard: hansard
                        ))
                        if out.debates.count >= Self.maxPerSection { break outer }
                    }
                }
            }
        }

        return out
    }
}
