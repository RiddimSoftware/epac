//
//  HomeLiveCardDecision.swift
//  epac
//

import Foundation

/// The pre-computed live-card display decision, moved out of the view layer.
enum HomeLiveCardDecision: Equatable {
    case live(LiveParliamentStatus)
    case todayPublished(hansardID: String, date: Date, subjectTitle: String)
    case todayPending
    case hidden
}
