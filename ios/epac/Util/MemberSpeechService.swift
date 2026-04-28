import Foundation

// Response types matching the member-speeches Lambda (EPAC-293).

private let memberSpeechISODateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

struct MemberSpeechEntry: Identifiable, Decodable {
    let id: String              // intervention_id
    let sittingDate: String?
    let parliamentNum: Int?
    let sessionNum: Int?
    let subjectTitle: String?
    let preview: String
    let wordCount: Int?
    let filename: String

    enum CodingKeys: String, CodingKey {
        case id
        case sittingDate  = "sitting_date"
        case parliamentNum = "parliament_num"
        case sessionNum    = "session_num"
        case subjectTitle  = "subject_title"
        case preview
        case wordCount     = "word_count"
        case filename
    }

    var parsedDate: Date? {
        guard let s = sittingDate else { return nil }
        return memberSpeechISODateFormatter.date(from: s)
    }
}

struct MemberStats: Decodable {
    let totalSpeeches: Int
    let avgWordCount: Int
    let topTopic: String

    enum CodingKeys: String, CodingKey {
        case totalSpeeches = "total_speeches"
        case avgWordCount  = "avg_word_count"
        case topTopic      = "top_topic"
    }
}

struct MemberSpeechesPage: Decodable {
    let memberId: String
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int
    let stats: MemberStats
    let speeches: [MemberSpeechEntry]

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case page, perPage = "per_page"
        case total, pages, stats, speeches
    }
}

// Lightweight topic model built client-side from the fetched speeches.
struct SpeechTopicChip: Identifiable {
    let id: String   // subject_title
    var count: Int
}

enum MemberSpeechServiceError: Error {
    case badURL
    case networkError(Error)
    case decodeError(Error)
}

struct MemberSpeechService {
    static func fetchPage(memberId: Int, page: Int, perPage: Int = 20, topic: String? = nil) async throws -> MemberSpeechesPage {
        let base = BackendConfig.shared.baseURL.absoluteString
        var components = URLComponents(string: "\(base)/members/\(memberId)/speeches")!
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ]
        if let topic {
            queryItems.append(URLQueryItem(name: "topic", value: topic))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw MemberSpeechServiceError.badURL }

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await NetworkService.shared.data(from: url)
        } catch {
            throw MemberSpeechServiceError.networkError(error)
        }

        do {
            return try JSONDecoder().decode(MemberSpeechesPage.self, from: data)
        } catch {
            throw MemberSpeechServiceError.decodeError(error)
        }
    }
}
