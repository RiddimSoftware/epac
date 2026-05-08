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
    
    func execute() async -> HomeFeedSnapshot {
        let today = Calendar.current.startOfDay(for: clock.now)
        
        let calendars = (try? await repository.fetchSittingCalendars()) ?? []
        let allSittingDates = calendars.flatMap(\.sittings).map { Calendar.current.startOfDay(for: $0) }
        let isSittingToday = allSittingDates.contains { Calendar.current.isDate($0, inSameDayAs: today) }
        let nextSittingDate = allSittingDates.filter { $0 > today }.sorted().first
        
        let allMembers = (try? await repository.fetchAllMembers()) ?? []
        let savedMemberName = followPreferenceReading.savedMemberName()
        var followedMember: ParliamentMember? = nil
        if let name = savedMemberName {
            followedMember = allMembers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }
        
        var myMPActivityCount = 0
        var provinceAbbrev = ""
        var mySenators: [Senator] = []
        
        if let name = savedMemberName {
            let lastName = name.components(separatedBy: " ").last ?? name
            let msgs = (try? await repository.fetchSpeechMessages(for: lastName)) ?? []
            myMPActivityCount = msgs.filter {
                $0.lastName.localizedCaseInsensitiveContains(lastName)
            }.count
            
            if let mp = followedMember {
                provinceAbbrev = mp.province.shortCode
                if !provinceAbbrev.isEmpty {
                    mySenators = (try? await repository.fetchSenators()) ?? []
                }
            }
        }
        
        let hansards = (try? await repository.fetchLatestHansards(limit: 10)) ?? []
        let latestHansard = hansards.first
        
        let liveParliamentStatus = try? await liveParliamentStatusFetching.fetchStatus()
        
        var parliamentDayStatus = resolveParliamentDayStatus(today: today, latestHansard: latestHansard)
        if liveParliamentStatus?.isSitting == true {
            parliamentDayStatus = .sitting
        }
        
        let recentSubjects = Array(
            (hansards.first?.orders.flatMap { $0.subjects } ?? []).prefix(3)
        )
        let latestSpeechHighlight = makeLatestSpeechHighlight(for: followedMember, in: hansards)
        
        let latestRecordedVote = try? await repository.fetchLatestRecordedVote()
        
        var latestMemberVote: MemberVote? = nil
        if let memberID = followedMember?.memberID, let voteID = latestRecordedVote?.voteID {
            latestMemberVote = try? await repository.fetchMemberVote(memberID: memberID, voteID: voteID)
        }
        
        var postSittingHansard: Hansard? = nil
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
        
        let onThisDayItems = (try? await onThisDayFetching.fetch(date: clock.now, limit: 5)) ?? []
        
        let civicContext = FollowedCivicContext(
            followedBills: followPreferenceReading.followedBillNumbers(),
            followedTopics: followPreferenceReading.followedTopicIDs(),
            mySenators: mySenators,
            provinceAbbrev: provinceAbbrev
        )
        
        return HomeFeedSnapshot(
            isSittingToday: isSittingToday,
            parliamentDayStatus: parliamentDayStatus,
            liveParliamentStatus: liveParliamentStatus,
            nextSittingDate: nextSittingDate,
            followedMember: followedMember,
            myMPActivityCount: myMPActivityCount,
            civicContext: civicContext,
            recentSubjects: recentSubjects,
            latestHansard: latestHansard,
            postSittingHansard: postSittingHansard,
            latestSpeechHighlight: latestSpeechHighlight,
            latestRecordedVote: latestRecordedVote,
            latestMemberVote: latestMemberVote,
            onThisDayItems: onThisDayItems
        )
    }
    
    private func resolveParliamentDayStatus(today: Date, latestHansard: Hansard?) -> HomeParliamentDayStatus {
        guard let latest = latestHansard else { return .notSitting }
        if Calendar.current.isDate(latest.date, inSameDayAs: today) {
            return .adjourned
        }
        return .notSitting
    }
    
    private func makeLatestSpeechHighlight(for mp: ParliamentMember?, in hansards: [Hansard]) -> HomeSpeechHighlight? {
        guard let member = mp else { return nil }
        let lastName = member.lastName
        for hansard in hansards {
            for order in hansard.orders {
                for subject in order.subjects {
                    for speech in subject.speeches {
                        for message in speech.messages {
                            if message.lastName.localizedCaseInsensitiveCompare(lastName) == .orderedSame {
                                return HomeSpeechHighlight(
                                    hansard: hansard,
                                    subject: subject,
                                    memberName: member.name,
                                    excerpt: trimmedExcerpt(message.content)
                                )
                            }
                        }
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
