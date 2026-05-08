import Foundation

struct HansardSearchDocument: Sendable, Equatable {
    let subjectID: String
    let subjectTitle: String
    let hansardDate: Date
}

protocol HansardSearchStore {
    @MainActor func loadDocuments() throws -> [HansardSearchDocument]
}

protocol SearchHansardUseCase {
    @MainActor func execute(query: String) -> [SearchHansard.Match]
}

struct SearchHansard: SearchHansardUseCase {
    struct Match: Identifiable, Sendable, Equatable {
        let subjectID: String
        let subjectTitle: String
        let hansardDate: Date

        var id: String { subjectID }
    }

    private static let maxResults = 50

    let store: any HansardSearchStore

    @MainActor
    func execute(query: String) -> [Match] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2,
              let documents = try? store.loadDocuments() else {
            return []
        }

        return Array(
            documents.lazy
                .filter { $0.subjectTitle.localizedCaseInsensitiveContains(trimmedQuery) }
                .prefix(Self.maxResults)
                .map {
                    Match(
                        subjectID: $0.subjectID,
                        subjectTitle: $0.subjectTitle,
                        hansardDate: $0.hansardDate
                    )
                }
        )
    }
}

private struct EmptyHansardSearchStore: HansardSearchStore {
    @MainActor
    func loadDocuments() throws -> [HansardSearchDocument] { [] }
}

extension SearchHansard {
    static func empty() -> SearchHansard {
        SearchHansard(store: EmptyHansardSearchStore())
    }
}
