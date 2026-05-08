import Foundation

@MainActor
final class CachingHansardSearchStore: HansardSearchStore {
    private let base: any HansardSearchStore
    private var cachedDocuments: [HansardSearchDocument]?

    init(base: any HansardSearchStore) {
        self.base = base
    }

    func loadDocuments() throws -> [HansardSearchDocument] {
        if let cachedDocuments {
            return cachedDocuments
        }

        let documents = try base.loadDocuments()
        cachedDocuments = documents
        return documents
    }
}
