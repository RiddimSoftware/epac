//
//  LiveParliamentStatus.swift
//  epac
//

import Foundation

struct LiveParliamentStatus: Decodable, Equatable {
    enum Status: String, Decodable {
        case sitting
        case adjourned
        case unknown
    }

    let status: Status
    let isSitting: Bool
    let businessType: String
    let currentItemTitle: String?
    let currentBillNumber: String?
    let currentSpeakerName: String?
    let divisionInProgress: Bool
    let checkedAt: Date
    let lastChangedAt: Date?
    /// YYYY-MM-DD calendar date (Ottawa-local) of the current or most-recent sitting.
    let sittingDate: String?
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case status
        case isSitting = "is_sitting"
        case businessType = "business_type"
        case currentItemTitle = "current_item_title"
        case currentBillNumber = "current_bill_number"
        case currentSpeakerName = "current_speaker_name"
        case divisionInProgress = "division_in_progress"
        case checkedAt = "checked_at"
        case lastChangedAt = "last_changed_at"
        case sittingDate = "sitting_date"
        case sourceURL = "source_url"
    }
}
