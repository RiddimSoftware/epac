//
//  LoadHomeFeed.swift
//  epac
//

import Foundation

@MainActor
struct LoadHomeFeed {
    private static let latestHansardsLimit: Int = 10
    private static let recentSubjectTitleCount: Int = 3
    private static let excerptMaxLength: Int = 140

    private let repository: HomeFeedRepository
    private let followPreferenceReading: FollowPreferenceReading
    private let clock: Clock

    init(
        repository: HomeFeedRepository,
        followPreferenceReading: FollowPreferenceReading,
        clock: Clock = SystemClock()
    ) {
        self.repository = repository
        self.followPreferenceReading = followPreferenceReading
        self.clock = clock
    }

    func execute() async -> HomeFeedSnapshot {
        let today = Calendar.current.startOfDay(for: clock.now)

        let sittingDates = (try? await repository.fetchSittingDates()) ?? []
        let isSittingToday = sittingDates.contains { Calendar.current.isDate($0, inSameDayAs: today) }
        let nextSittingDate = sittingDates.filter { $0 > today }.sorted().first

        let allMembers = (try? await repository.fetchAllMembers()) ?? []
        let savedMemberName = followPreferenceReading.savedMemberName()
        let followedMemberIDs = followPreferenceReading.followedMemberIDs()
        let followedMember = resolveFollowedMember(from: allMembers, savedName: savedMemberName, followedIDs: followedMemberIDs)

        let myMPActivityCount: Int
        if let lastName = followedMember?.lastName
            ?? savedMemberName.map({ $0.components(separatedBy: " ").last ?? $0 }) {
            myMPActivityCount = (try? await repository.fetchMPActivityCount(for: lastName)) ?? 0
        } else {
            myMPActivityCount = 0
        }

        let mySenators: [Senator]
        let provinceAbbrev: String
        if let mp = followedMember, !mp.provinceCode.isEmpty {
            provinceAbbrev = mp.provinceCode
            mySenators = (try? await repository.fetchSenators(for: provinceAbbrev)) ?? []
        } else {
            provinceAbbrev = ""
            mySenators = []
        }

        let hansards = (try? await repository.fetchLatestHansards(limit: Self.latestHansardsLimit)) ?? []
        let latestHansard = hansards.first

        let parliamentDayStatus = resolveParliamentDayStatus(today: today, latestHansard: latestHansard, isSittingToday: isSittingToday)

        let recentSubjectTitles = Array(
            (hansards.first?.subjectRecords.map(\.title) ?? []).prefix(Self.recentSubjectTitleCount)
        )
        let latestSpeechHighlight = makeLatestSpeechHighlight(for: followedMember, in: hansards)

        let latestVote = try? await repository.fetchLatestVote()

        var latestMemberVote: HomeMemberVoteRecord?
        if let memberID = followedMember?.memberID, let voteID = latestVote?.voteID {
            latestMemberVote = try? await repository.fetchMemberVote(memberID: memberID, voteID: voteID)
        }

        let civicContext = FollowedCivicContext(
            followedBills: followPreferenceReading.followedBillNumbers(),
            followedTopics: followPreferenceReading.followedTopicIDs(),
            mySenators: mySenators,
            provinceAbbrev: provinceAbbrev
        )

        let hasPersonalizedContext = savedMemberName != nil
            || !followPreferenceReading.followedMemberIDs().isEmpty
            || !followPreferenceReading.followedBillNumbers().isEmpty
            || !followPreferenceReading.followedTopicIDs().isEmpty

        return HomeFeedSnapshot(
            isSittingToday: isSittingToday,
            parliamentDayStatus: parliamentDayStatus,
            nextSittingDate: nextSittingDate,
            followedMember: followedMember,
            myMPActivityCount: myMPActivityCount,
            savedMemberName: savedMemberName,
            hasPersonalizedContext: hasPersonalizedContext,
            civicContext: civicContext,
            recentSubjectTitles: recentSubjectTitles,
            latestHansardDate: latestHansard?.date,
            latestSpeechHighlight: latestSpeechHighlight,
            latestVote: latestVote,
            latestMemberVote: latestMemberVote
        )
    }

    private func resolveFollowedMember(from members: [HomeFollowedMember], savedName: String?, followedIDs: [Int]) -> HomeFollowedMember? {
        if let savedName,
           let match = members.first(where: {
               $0.name.localizedCaseInsensitiveContains(savedName) ||
               savedName.localizedCaseInsensitiveContains($0.lastName)
           }) {
            return match
        }
        if let followedID = followedIDs.first {
            return members.first { $0.memberID == followedID }
        }
        return nil
    }

    private func resolveParliamentDayStatus(today: Date, latestHansard: HomeHansardRecord?, isSittingToday: Bool) -> HomeParliamentDayStatus {
        guard isSittingToday else { return .notSitting }
        if let latest = latestHansard, Calendar.current.isDate(latest.date, inSameDayAs: today) {
            return .adjourned
        }
        return .sitting
    }

    private func makeLatestSpeechHighlight(for mp: HomeFollowedMember?, in hansards: [HomeHansardRecord]) -> HomeSpeechHighlight? {
        guard let member = mp else { return nil }
        let lastName = member.lastName
        for hansard in hansards {
            for subject in hansard.subjectRecords {
                for message in subject.messages {
                    if message.lastName.localizedCaseInsensitiveCompare(lastName) == .orderedSame {
                        return HomeSpeechHighlight(
                            hansardID: hansard.hansardID,
                            hansardDate: hansard.date,
                            subjectTitle: subject.title,
                            memberName: member.name,
                            excerpt: trimmedExcerpt(message.content)
                        )
                    }
                }
            }
        }
        return nil
    }

    private func trimmedExcerpt(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > Self.excerptMaxLength else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: Self.excerptMaxLength)
        return String(cleaned[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
