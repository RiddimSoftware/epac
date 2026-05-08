//
//  SearchViewModel.swift
//  epac
//

import Foundation
import Observation
import SwiftData

// Filters cached parliamentary data across four corpora: MPs, votes, bills, debate subjects.
// Results per section are capped to keep SwiftUI responsive on large datasets.
@MainActor
@Observable
class SearchViewModel {
    var searchText = ""
    var searchResults = SearchResults()

    private static let maxPerSection = 50
    private var searchHansard: any SearchHansardUseCase = SearchHansard.empty()

    // MARK: - Result types

    struct MemberResult: Identifiable {
        let id: Int  // memberID
        let member: ParliamentMember
    }

    struct VoteResult: Identifiable {
        let id: Int  // voteID
        let vote: RecordedVote
    }

    struct BillResult: Identifiable {
        let id: String  // bill number
        let bill: Bill
    }

    struct DebateResult: Identifiable {
        let id: String  // subject hansardID
        let hansardDate: Date
        let subjectID: String
        let subjectTitle: String
    }

    struct SearchResults {
        var members: [MemberResult] = []
        var votes: [VoteResult] = []
        var bills: [BillResult] = []
        var debates: [DebateResult] = []

        var isEmpty: Bool { members.isEmpty && votes.isEmpty && bills.isEmpty && debates.isEmpty }
    }

    var isQueryTooShort: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
    }

    func configure(searchHansard: any SearchHansardUseCase) {
        self.searchHansard = searchHansard
    }

    func updateResults(
        members: [ParliamentMember],
        votes: [RecordedVote],
        bills: [Bill],
        query: String? = nil
    ) {
        let q = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            searchResults = SearchResults()
            return
        }

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

        // Bills: match bill number or title
        for bill in bills {
            if bill.number.localizedCaseInsensitiveContains(q)
                || bill.title.localizedCaseInsensitiveContains(q) {
                out.bills.append(BillResult(id: bill.number, bill: bill))
                if out.bills.count >= 10 { break }
            }
        }

        out.debates = searchHansard.execute(query: q).map { match in
            DebateResult(
                id: match.id,
                hansardDate: match.hansardDate,
                subjectID: match.subjectID,
                subjectTitle: match.subjectTitle
            )
        }

        searchResults = out
    }
    
    func resolveDebate(_ result: DebateResult, modelContext: ModelContext) -> (Hansard?, SubjectOfBusiness?) {
        let hansardDate = result.hansardDate
        let subjectID = result.subjectID

        let hansardDescriptor = FetchDescriptor<Hansard>(
            predicate: #Predicate { $0.date == hansardDate }
        )
        let subjectDescriptor = FetchDescriptor<SubjectOfBusiness>(
            predicate: #Predicate { $0.hansardID == subjectID }
        )

        let hansard = try? modelContext.fetch(hansardDescriptor).first
        let subject = try? modelContext.fetch(subjectDescriptor).first
        
        return (hansard, subject)
    }
}
