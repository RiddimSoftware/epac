//
//  HomeFeedSwiftDataRepository.swift
//  epac
//

import Foundation
import SwiftData

@MainActor
struct HomeFeedSwiftDataRepository: HomeFeedRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchSittingDates() async throws -> [Date] {
        let calendars = try modelContext.fetch(FetchDescriptor<SittingCalendar>())
        return calendars.flatMap(\.sittings)
    }

    func fetchAllMembers() async throws -> [HomeFollowedMember] {
        let members = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
        return members.map { toHomeFollowedMember($0) }
    }

    func fetchMPActivityCount(for lastName: String) async throws -> Int {
        let messages = try modelContext.fetch(FetchDescriptor<SpeechMessage>())
        return messages.filter {
            $0.lastName.localizedCaseInsensitiveContains(lastName)
        }.count
    }

    func fetchLatestHansards(limit: Int) async throws -> [HomeHansardRecord] {
        var descriptor = FetchDescriptor<Hansard>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        let hansards = try modelContext.fetch(descriptor)
        return hansards.map { toHomeHansardRecord($0) }
    }

    func fetchHansards(between start: Date, and end: Date) async throws -> [HomeHansardRecord] {
        let descriptor = FetchDescriptor<Hansard>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let hansards = try modelContext.fetch(descriptor)
        return hansards.map { toHomeHansardRecord($0) }
    }

    func fetchLatestVote() async throws -> HomeVoteRecord? {
        var descriptor = FetchDescriptor<RecordedVote>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let vote = try modelContext.fetch(descriptor).first else { return nil }
        return toHomeVoteRecord(vote)
    }

    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> HomeMemberVoteRecord? {
        var descriptor = FetchDescriptor<MemberVote>(
            predicate: #Predicate<MemberVote> { $0.memberID == memberID && $0.voteID == voteID },
            sortBy: [SortDescriptor(\.voteID, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let mv = try modelContext.fetch(descriptor).first else { return nil }
        return HomeMemberVoteRecord(voteID: mv.voteID, memberID: mv.memberID, recordedVote: mv.recordedVote)
    }

    func fetchSenators(for provinceAbbrev: String) async throws -> [Senator] {
        let allSenators = await SenatorsService.fetchSenators()
        return SenatorsService.senators(for: provinceAbbrev, from: allSenators)
    }

    // MARK: - Conversion helpers

    private func toHomeFollowedMember(_ member: ParliamentMember) -> HomeFollowedMember {
        HomeFollowedMember(
            memberID: member.memberID,
            name: member.name,
            lastName: member.lastName,
            provinceCode: member.province.shortCode
        )
    }

    private func toHomeHansardRecord(_ hansard: Hansard) -> HomeHansardRecord {
        let subjectRecords = hansard.orders.flatMap(\.subjects).map { subject in
            HomeHansardRecord.SubjectRecord(
                title: subject.title,
                messages: subject.speeches.flatMap(\.messages).map { msg in
                    HomeHansardRecord.MessageRecord(lastName: msg.lastName, content: msg.content)
                }
            )
        }
        return HomeHansardRecord(hansardID: hansard.hansardID, date: hansard.date, subjectRecords: subjectRecords)
    }

    private func toHomeVoteRecord(_ vote: RecordedVote) -> HomeVoteRecord {
        HomeVoteRecord(
            voteID: vote.voteID,
            number: vote.number,
            descriptionEn: vote.descriptionEn,
            billNumberCode: vote.billNumberCode,
            resultEn: vote.resultEn,
            date: vote.date,
            yea: vote.yea,
            nay: vote.nay,
            paired: vote.paired
        )
    }
}
