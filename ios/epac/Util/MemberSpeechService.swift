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

private struct MemberSpeechesArtifact: Decodable {
    let memberId: String
    let stats: MemberStats
    let speeches: [MemberSpeechEntry]

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case stats
        case speeches
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
    static func fetchPage(
        memberId: Int,
        page: Int,
        perPage: Int = 20,
        topic: String? = nil,
        artifacts: any ArtifactFetching = ArtifactService.shared
    ) async throws -> MemberSpeechesPage {
        let page = max(1, page)
        let perPage = min(max(1, perPage), 100)

        let artifact: MemberSpeechesArtifact
        do {
            artifact = try await artifacts.fetch(.memberSpeeches(memberID: memberId), as: MemberSpeechesArtifact.self)
        } catch let error as DecodingError {
            throw MemberSpeechServiceError.decodeError(error)
        } catch {
            throw MemberSpeechServiceError.networkError(error)
        }

        let filtered = artifact.speeches
            .filter { entry in
                guard let topic, !topic.isEmpty else { return true }
                return entry.subjectTitle?.localizedCaseInsensitiveContains(topic) == true
            }
            .sorted(by: Self.speechAfter)
        let total = filtered.count
        let start = min((page - 1) * perPage, total)
        let end = min(start + perPage, total)

        return MemberSpeechesPage(
            memberId: artifact.memberId,
            page: page,
            perPage: perPage,
            total: total,
            pages: total == 0 ? 0 : Int(ceil(Double(total) / Double(perPage))),
            stats: Self.stats(from: artifact),
            speeches: Array(filtered[start..<end])
        )
    }

    private static func stats(from artifact: MemberSpeechesArtifact) -> MemberStats {
        guard artifact.stats.totalSpeeches == 0, !artifact.speeches.isEmpty else {
            return artifact.stats
        }
        let wordCounts = artifact.speeches.compactMap(\.wordCount)
        let topicCounts = Dictionary(grouping: artifact.speeches.compactMap(\.subjectTitle), by: { $0 })
        let topTopic = topicCounts.max { lhs, rhs in lhs.value.count < rhs.value.count }?.key ?? ""
        return MemberStats(
            totalSpeeches: artifact.speeches.count,
            avgWordCount: wordCounts.isEmpty ? 0 : wordCounts.reduce(0, +) / wordCounts.count,
            topTopic: topTopic
        )
    }

    private static func speechAfter(_ lhs: MemberSpeechEntry, _ rhs: MemberSpeechEntry) -> Bool {
        switch (lhs.parsedDate, rhs.parsedDate) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id < rhs.id
        }
    }
}
