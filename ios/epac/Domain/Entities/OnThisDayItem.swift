//
//  OnThisDayItem.swift
//  epac
//

import Foundation

private let onThisDayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/Toronto")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

enum OnThisDayKind: String, Decodable {
    case speech
    case vote
}

struct OnThisDayItem: Identifiable, Decodable, Equatable {
    let id: String
    let kind: OnThisDayKind
    let year: Int
    let date: String
    let title: String
    let excerpt: String
    let speakerName: String?
    let memberID: String?
    let subjectTitle: String?
    let interventionID: String?
    let voteID: String?
    let billNumber: String?
    let sourceURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case year
        case date
        case title
        case excerpt
        case speakerName = "speaker_name"
        case memberID = "member_id"
        case subjectTitle = "subject_title"
        case interventionID = "intervention_id"
        case voteID = "vote_id"
        case billNumber = "bill_number"
        case sourceURL = "source_url"
    }

    var parsedDate: Date? {
        onThisDayDateFormatter.date(from: date)
    }

    var detailText: String {
        if let speakerName, !speakerName.isEmpty {
            return "\(year) · \(speakerName)"
        }
        return String(year)
    }
}
