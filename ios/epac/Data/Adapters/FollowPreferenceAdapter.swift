//
//  FollowPreferenceAdapter.swift
//  epac
//

import Foundation

@MainActor
struct FollowPreferenceAdapter: FollowPreferenceReading, FollowedBillReadPort {
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

    func fetchFollowedBills() async throws -> [FollowedBillRecord] {
        let store = BillFollowStore.shared
        return store.orderedBillNumbers.compactMap { number in
            guard let state = store.followed[number] else { return nil }
            return FollowedBillRecord(
                number: number,
                lastKnownStatus: state.lastKnownStatus,
                lastKnownStage: state.lastKnownStage,
                followedAt: state.followedAt,
                hasUnreadUpdate: state.hasUnreadUpdate ?? false
            )
        }
    }
}

