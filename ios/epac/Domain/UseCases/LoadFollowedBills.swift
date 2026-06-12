//
//  LoadFollowedBills.swift
//  epac
//
//  Created on 2026-06-12.
//

import Foundation

@MainActor
struct LoadFollowedBills {
    private let followedBillReadPort: any FollowedBillReadPort
    private let billStatusReadPort: any BillStatusReadPort

    init(followedBillReadPort: any FollowedBillReadPort, billStatusReadPort: any BillStatusReadPort) {
        self.followedBillReadPort = followedBillReadPort
        self.billStatusReadPort = billStatusReadPort
    }

    func execute() async throws -> [FollowedBill] {
        let records = try await followedBillReadPort.fetchFollowedBills()
        guard !records.isEmpty else { return [] }

        // Fetch fresh bills from LEGISinfo / backend API
        let freshBills = try await billStatusReadPort.fetchBills()
        let freshBillsMap = Dictionary(uniqueKeysWithValues: freshBills.map { ($0.number, $0) })

        return records.compactMap { record in
            if let freshBill = freshBillsMap[record.number] {
                return FollowedBill(
                    number: freshBill.number,
                    title: freshBill.title,
                    status: freshBill.status,
                    currentStage: freshBill.currentStage,
                    lastUpdateTimestamp: freshBill.introducedDate ?? record.followedAt,
                    hasUnreadUpdate: record.hasUnreadUpdate,
                    bill: freshBill
                )
            } else {
                // Fallback if the followed bill is not in the fetched list
                return FollowedBill(
                    number: record.number,
                    title: record.number, // Fallback title
                    status: BillStatus(rawValue: record.lastKnownStatus) ?? .unknown,
                    currentStage: record.lastKnownStage,
                    lastUpdateTimestamp: record.followedAt,
                    hasUnreadUpdate: record.hasUnreadUpdate,
                    bill: nil
                )
            }
        }
    }
}
