//
//  BillSharer.swift
//  epac
//

import ActivityView
import Foundation

// Generates an ActivityItem share payload for a bill with verified source links.
// The Universal Link opens epac if installed; falls back to App Store.
// legisInfoURL (Parliament of Canada LEGISinfo) is included as the verifiable source.
enum BillSharer {
    static func activityItem(for bill: Bill) -> ActivityItem {
        let universalLink = url(for: bill)
        let text = shareText(for: bill, universalLink: universalLink)
        return ActivityItem(items: text, universalLink)
    }

    private static func url(for bill: Bill) -> URL {
        let encoded = bill.number.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bill.number
        return URL(string: "https://epac.riddimsoftware.com/bill/\(bill.parliament)-\(bill.session)/\(encoded)/")
            ?? URL(string: "https://epac.riddimsoftware.com")!
    }

    private static func shareText(for bill: Bill, universalLink: URL) -> String {
        let statusLine: String
        switch bill.status {
        case .royalAssent: statusLine = "✅ Received Royal Assent"
        case .defeated:    statusLine = "❌ Defeated"
        case .inProgress:  statusLine = "🔄 \(bill.currentStage)"
        case .unknown:     statusLine = bill.currentStage
        }

        var lines = ["📋 \(bill.number) — \(bill.title)", statusLine]
        if let date = bill.introducedDate {
            lines.append("Introduced: \(date.formatted(date: .long, time: .omitted))")
        }
        lines += ["", universalLink.absoluteString, "Official source: \(bill.legisInfoURL.absoluteString)"]
        return lines.joined(separator: "\n")
    }
}
