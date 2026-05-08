//
//  HomeHansardRecord.swift
//  epac
//

import Foundation

/// Framework-free domain representation of a Hansard and its speech content.
struct HomeHansardRecord {
    struct SubjectRecord {
        let title: String
        /// All speaker messages across all speeches in this subject, in order.
        let messages: [MessageRecord]
    }

    struct MessageRecord {
        let lastName: String
        let content: String
    }

    let hansardID: String
    let date: Date
    /// All subjects across all orders, flattened in order.
    let subjectRecords: [SubjectRecord]

    /// Top N subject titles, for display.
    func recentSubjectTitles(limit: Int) -> [String] {
        Array(subjectRecords.prefix(limit).map(\.title))
    }
}
