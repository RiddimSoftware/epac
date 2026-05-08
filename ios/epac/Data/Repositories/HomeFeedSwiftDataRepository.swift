//
//  HomeFeedSwiftDataRepository.swift
//  epac
//

import SwiftData
import Foundation

@MainActor
struct HomeFeedSwiftDataRepository: HomeFeedRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchSittingCalendars() async throws -> [SittingCalendar] {
        try modelContext.fetch(FetchDescriptor<SittingCalendar>())
    }
    
    func fetchAllMembers() async throws -> [ParliamentMember] {
        try modelContext.fetch(FetchDescriptor<ParliamentMember>())
    }
    
    func fetchSpeechMessages(for lastName: String) async throws -> [SpeechMessage] {
        try modelContext.fetch(FetchDescriptor<SpeechMessage>())
    }
    
    func fetchLatestHansards(limit: Int) async throws -> [Hansard] {
        var descriptor = FetchDescriptor<Hansard>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
    
    func fetchHansards(between start: Date, and end: Date) async throws -> [Hansard] {
        let descriptor = FetchDescriptor<Hansard>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return try modelContext.fetch(descriptor)
    }
    
    func fetchLatestRecordedVote() async throws -> RecordedVote? {
        var descriptor = FetchDescriptor<RecordedVote>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> MemberVote? {
        var descriptor = FetchDescriptor<MemberVote>(
            predicate: #Predicate<MemberVote> { $0.memberID == memberID && $0.voteID == voteID },
            sortBy: [SortDescriptor(\.voteID, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    func fetchSenators(for provinceAbbrev: String) async throws -> [Senator] {
        let allSenators = await SenatorsService.fetchSenators()
        return SenatorsService.senators(for: provinceAbbrev, from: allSenators)
    }
}
