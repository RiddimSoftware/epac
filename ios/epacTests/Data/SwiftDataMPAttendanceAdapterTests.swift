//
//  SwiftDataMPAttendanceAdapterTests.swift
//  epacTests
//
//  Tests for SwiftDataMPAttendanceAdapter (EPAC-897).
//

@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
struct SwiftDataMPAttendanceAdapterTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(versionedSchema: SchemaV11.self), configurations: config)
    }

    @Test func tallyReturnsNilWhenNoRecordedVotesInSystem() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let adapter = SwiftDataMPAttendanceAdapter(modelContext: context)

        let result = try await adapter.tally(forMemberID: 1)
        #expect(result == nil)
    }

    @Test func tallyReturnsNilWhenMemberDoesNotExist() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Insert a division so divisionDates is not empty
        let vote = RecordedVote(
            voteID: 100,
            parliament: 44,
            session: 1,
            number: 1,
            date: Date(),
            descriptionEn: "Test division",
            billNumberCode: "C-11",
            yea: 0, nay: 0, paired: 0,
            resultEn: "Carried"
        )
        context.insert(vote)

        let adapter = SwiftDataMPAttendanceAdapter(modelContext: context)
        let result = try await adapter.tally(forMemberID: 999)
        #expect(result == nil)
    }

    @Test func tallyComputesCorrectTalliesForMember() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let swornInDate = Date().addingTimeInterval(-3600 * 24 * 5) // 5 days ago
        let oldDate = Date().addingTimeInterval(-3600 * 24 * 10) // 10 days ago (pre sworn-in)
        let newDate = Date().addingTimeInterval(-3600 * 24 * 2) // 2 days ago (post sworn-in)

        // Insert member
        let member = ParliamentMember(
            name: "John Doe",
            lastName: "Doe",
            firstName: "John",
            photoURL: URL(string: "https://example.com/photo.jpg")!,
            riding: "Ottawa Centre",
            province: .Ontario,
            party: .liberal,
            memberID: 42,
            fromDateTime: swornInDate
        )
        context.insert(member)

        // Insert votes (divisions)
        let division1 = RecordedVote(voteID: 101, parliament: 44, session: 1, number: 1, date: oldDate, descriptionEn: "Old", billNumberCode: "C-1", yea: 0, nay: 0, paired: 0, resultEn: "Carried")
        let division2 = RecordedVote(voteID: 102, parliament: 44, session: 1, number: 2, date: newDate, descriptionEn: "New Yea", billNumberCode: "C-2", yea: 0, nay: 0, paired: 0, resultEn: "Carried")
        let division3 = RecordedVote(voteID: 103, parliament: 44, session: 1, number: 3, date: newDate, descriptionEn: "New Nay", billNumberCode: "C-3", yea: 0, nay: 0, paired: 0, resultEn: "Carried")
        let division4 = RecordedVote(voteID: 104, parliament: 44, session: 1, number: 4, date: newDate, descriptionEn: "New Paired", billNumberCode: "C-4", yea: 0, nay: 0, paired: 0, resultEn: "Carried")
        let division5 = RecordedVote(voteID: 105, parliament: 44, session: 1, number: 5, date: newDate, descriptionEn: "New Absent", billNumberCode: "C-5", yea: 0, nay: 0, paired: 0, resultEn: "Carried")
        
        context.insert(division1)
        context.insert(division2)
        context.insert(division3)
        context.insert(division4)
        context.insert(division5)

        // Member's votes
        // Note: old vote (pre-sworn in) is counted on division1 but should be filtered out by the adapter
        let mv1 = MemberVote(voteID: 101, memberID: 42, recordedVote: "yea")
        let mv2 = MemberVote(voteID: 102, memberID: 42, recordedVote: "yea")
        let mv3 = MemberVote(voteID: 103, memberID: 42, recordedVote: "nay")
        let mv4 = MemberVote(voteID: 104, memberID: 42, recordedVote: "paired")
        let mv5 = MemberVote(voteID: 105, memberID: 42, recordedVote: "absent")

        context.insert(mv1)
        context.insert(mv2)
        context.insert(mv3)
        context.insert(mv4)
        context.insert(mv5)

        let adapter = SwiftDataMPAttendanceAdapter(modelContext: context)
        let tally = try await adapter.tally(forMemberID: 42)

        let result = try #require(tally)
        #expect(result.memberID == 42)
        #expect(result.party == .liberal)
        #expect(result.yea == 1) // mv2 (yea). mv1 is ignored because it's before swornInDate.
        #expect(result.nay == 1) // mv3 (nay)
        #expect(result.paired == 1) // mv4 (paired)
        #expect(result.totalDivisions == 4) // division2, 3, 4, 5 (all >= swornInDate). division1 is ignored.
        #expect(result.denominatorStartDate == swornInDate)
    }
}
