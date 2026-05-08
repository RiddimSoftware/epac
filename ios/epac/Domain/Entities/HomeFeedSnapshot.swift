//
//  HomeFeedSnapshot.swift
//  epac
//

import Foundation

struct FollowedCivicContext {
    let followedBills: [String]
    let followedTopics: [String]
    let mySenators: [Senator]
    let provinceAbbrev: String
}

struct HomeSpeechHighlight {
    let hansardID: String
    let hansardDate: Date
    let subjectTitle: String
    let memberName: String
    let excerpt: String
}

enum HomeParliamentDayStatus {
    case sitting
    case adjourned
    case notSitting
}

struct HomeFeedSnapshot {
    let isSittingToday: Bool
    let parliamentDayStatus: HomeParliamentDayStatus
    let liveParliamentStatus: LiveParliamentStatus?
    let liveCardDecision: HomeLiveCardDecision
    let nextSittingDate: Date?

    let followedMember: HomeFollowedMember?
    let myMPActivityCount: Int
    let savedMemberName: String?
    let hasPersonalizedContext: Bool

    let civicContext: FollowedCivicContext

    let recentSubjectTitles: [String]
    let latestHansardDate: Date?
    let latestSpeechHighlight: HomeSpeechHighlight?

    let latestVote: HomeVoteRecord?
    let latestMemberVote: HomeMemberVoteRecord?

    let onThisDayItems: [OnThisDayItem]
}
