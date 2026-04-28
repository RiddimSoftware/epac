//
//  ParlVULinkBuilder.swift
//  epac
//
//  Created on 2026-04-28.
//

import Foundation

enum ParlVULinkBuilder {
    private static let houseOfCommonsChamberID = "39389"
    private static let baseURL = URL(string: "https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2")!
    private static let committeeArchiveURL = URL(string: "https://parlvu.parl.gc.ca/harmony/en")!

    static func houseDebateURL(for date: Date) -> URL? {
        powerBrowserURL(dateSlug: DateUtils.getCSVStringFromDate(date), eventID: houseOfCommonsChamberID)
    }

    static func committeeWatchURL(for meeting: CommitteeMeeting) -> URL? {
        meeting.webcastURL
    }

    static var committeeArchiveHomeURL: URL {
        committeeArchiveURL
    }

    static func powerBrowserURL(dateSlug: String, eventID: String) -> URL? {
        guard !dateSlug.isEmpty, !eventID.isEmpty else { return nil }
        return baseURL
            .appending(path: dateSlug)
            .appending(path: "-1")
            .appending(path: eventID)
    }

    static func normalizedURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        return URL(string: trimmed)
    }

}
