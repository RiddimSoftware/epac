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
    
    func savedMemberName() -> String? {
        UserDefaults.standard.string(forKey: "epac.postalCode.savedMemberName")
    }
    
    func dismissedOnThisDayDate() -> String? {
        UserDefaults.standard.string(forKey: "epac.onThisDay.dismissedDate")
    }
    
    func dismissOnThisDay(dateString: String) {
        UserDefaults.standard.set(dateString, forKey: "epac.onThisDay.dismissedDate")
    }
}
