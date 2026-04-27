//
//  ReviewRequestManager.swift
//  epac
//
//  Tracks install date, open count, and last prompt date in UserDefaults,
//  and calls SKStoreReviewController.requestReview(in:) at high-engagement
//  trigger moments when gate conditions are met.
//

import StoreKit
import UIKit

@MainActor
final class ReviewRequestManager {
    @MainActor static let shared = ReviewRequestManager()

    private let installDateKey     = "epac.review.installDate"
    private let openCountKey       = "epac.review.openCount"
    private let lastPromptKey      = "epac.review.lastPromptDate"
    private let minDaysInstalled   = 7
    private let minOpenCount       = 5
    private let minDaysSincePrompt = 90

    private init() {}

    func recordAppOpen() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: installDateKey) == nil {
            defaults.set(Date(), forKey: installDateKey)
        }
        let count = defaults.integer(forKey: openCountKey)
        defaults.set(count + 1, forKey: openCountKey)
    }

    func requestReviewIfAppropriate() {
        guard meetsGateCriteria() else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
    }

    private func meetsGateCriteria() -> Bool {
        let defaults = UserDefaults.standard
        // Gate 1: installed ≥7 days ago
        guard let installDate = defaults.object(forKey: installDateKey) as? Date,
              Date().timeIntervalSince(installDate) >= Double(minDaysInstalled * 86400) else { return false }
        // Gate 2: opened ≥5 times
        guard defaults.integer(forKey: openCountKey) >= minOpenCount else { return false }
        // Gate 3: not prompted in last 90 days
        if let lastPrompt = defaults.object(forKey: lastPromptKey) as? Date {
            guard Date().timeIntervalSince(lastPrompt) >= Double(minDaysSincePrompt * 86400) else { return false }
        }
        return true
    }
}
