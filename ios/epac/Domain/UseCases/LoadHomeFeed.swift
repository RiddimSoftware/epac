//
//  LoadHomeFeed.swift
//  epac
//

import Foundation

@MainActor
struct LoadHomeFeed {
    private let repository: HomeFeedRepository
    private let liveParliamentStatusFetching: LiveParliamentStatusFetching
    private let onThisDayFetching: OnThisDayFetching
    private let followPreferenceReading: FollowPreferenceReading
    private let clock: Clock

    init(
        repository: HomeFeedRepository,
        liveParliamentStatusFetching: LiveParliamentStatusFetching,
        onThisDayFetching: OnThisDayFetching,
        followPreferenceReading: FollowPreferenceReading,
        clock: Clock = SystemClock()
    ) {
        self.repository = repository
        self.liveParliamentStatusFetching = liveParliamentStatusFetching
        self.onThisDayFetching = onThisDayFetching
        self.followPreferenceReading = followPreferenceReading
        self.clock = clock
    }

    // preservingOnThisDayItems: returned unchanged when the network fetch fails so
    // an offline pull-to-refresh doesn't erase the last successful snapshot.
    func execute(preservingOnThisDayItems existing: [OnThisDayItem] = []) async -> HomeFeedSnapshot {
        let today = Calendar.current.startOfDay(for: clock.now)
        let ottawaTodayString = makeOttawaTodayString(from: clock.now)

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

        let hansards = (try? await repository.fetchLatestHansards(limit: 10)) ?? []
        let latestHansard = hansards.first

        let liveParliamentStatus = try? await liveParliamentStatusFetching.fetchStatus()

        var parliamentDayStatus = resolveParliamentDayStatus(today: today, latestHansard: latestHansard, isSittingToday: isSittingToday)
        if liveParliamentStatus?.isSitting == true {
            parliamentDayStatus = .sitting
        }

        let recentSubjectTitles = Array(
            (hansards.first?.subjectRecords.map(\.title) ?? []).prefix(3)
        )
        let latestSpeechHighlight = makeLatestSpeechHighlight(for: followedMember, in: hansards)

        let latestVote = try? await repository.fetchLatestVote()

        var latestMemberVote: HomeMemberVoteRecord?
        if let memberID = followedMember?.memberID, let voteID = latestVote?.voteID {
            latestMemberVote = try? await repository.fetchMemberVote(memberID: memberID, voteID: voteID)
        }

        var postSittingHansard: HomeHansardRecord?
        if let status = liveParliamentStatus, !status.isSitting, let sittingDate = status.sittingDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "America/Toronto")
            if let date = formatter.date(from: sittingDate) {
                let start = Calendar.current.startOfDay(for: date)
                if let end = Calendar.current.date(byAdding: .day, value: 1, to: start) {
                    let matchingHansards = try? await repository.fetchHansards(between: start, and: end)
                    postSittingHansard = matchingHansards?.first
                }
            }
        }

        let liveCardDecision = computeLiveCardDecision(
            status: liveParliamentStatus,
            postSittingHansard: postSittingHansard,
            ottawaTodayString: ottawaTodayString
        )

        let onThisDayItems = (try? await onThisDayFetching.fetch(date: clock.now, limit: 5)) ?? existing

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
            liveParliamentStatus: liveParliamentStatus,
            liveCardDecision: liveCardDecision,
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
            latestMemberVote: latestMemberVote,
            onThisDayItems: onThisDayItems
        )
    }

    private func makeOttawaTodayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        return formatter.string(from: date)
    }

    private func computeLiveCardDecision(
        status: LiveParliamentStatus?,
        postSittingHansard: HomeHansardRecord?,
        ottawaTodayString: String
    ) -> HomeLiveCardDecision {
        guard let status else { return .hidden }
        if status.isSitting { return .live(status) }
        guard let sittingDate = status.sittingDate, sittingDate == ottawaTodayString else {
            return .hidden
        }
        if let hansard = postSittingHansard {
            let subjectTitle = hansard.subjectRecords.first?.title ?? ""
            return .todayPublished(hansardID: hansard.hansardID, date: hansard.date, subjectTitle: subjectTitle)
        }
        return .todayPending
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
        guard cleaned.count > 140 else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: 140)
        return String(cleaned[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
