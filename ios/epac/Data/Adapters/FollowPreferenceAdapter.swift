//
//  FollowPreferenceAdapter.swift
//  epac
//

import Foundation

@MainActor
struct FollowPreferenceAdapter: FollowPreferenceReading {
    func followedBillNumbers() -> [String] {
        Array(BillFollowStore.shared.followedNumbers)
    }
    
    func followedTopicIDs() -> [String] {
        Array(TopicFollowStore.shared.followedIDs)
    }
    
    func followedMemberIDs() -> [Int] {
        Array(MemberFollowStore.shared.followedIDs)
    }
    
    func savedMemberName() -> String? {
        PostalCodeStore.shared.savedMemberName
    }
}
