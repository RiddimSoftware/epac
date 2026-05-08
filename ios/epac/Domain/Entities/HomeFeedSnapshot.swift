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
    let hansard: Hansard
    let subject: SubjectOfBusiness
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
    let nextSittingDate: Date?
    
    let followedMember: ParliamentMember?
    let myMPActivityCount: Int
    
    let civicContext: FollowedCivicContext
    
    let recentSubjects: [SubjectOfBusiness]
    let latestHansard: Hansard?
    let postSittingHansard: Hansard?
    
    let latestSpeechHighlight: HomeSpeechHighlight?
    
    let latestRecordedVote: RecordedVote?
    let latestMemberVote: MemberVote?
    
    let onThisDayItems: [OnThisDayItem]
}
