@testable import epac
import Foundation
import Testing

@MainActor
struct SearchHansardTests {
    @Test func returnsMatchingSubjectsFromNewestFirstDocuments() {
        let useCase = SearchHansard(store: StubHansardSearchStore(documents: [
            HansardSearchDocument(subjectID: "a", subjectTitle: "Housing affordability", hansardDate: Date(timeIntervalSince1970: 200)),
            HansardSearchDocument(subjectID: "b", subjectTitle: "Climate adaptation", hansardDate: Date(timeIntervalSince1970: 100)),
            HansardSearchDocument(subjectID: "c", subjectTitle: "Affordable housing starts", hansardDate: Date(timeIntervalSince1970: 50))
        ]))

        let results = useCase.execute(query: "housing")

        #expect(results.map(\.subjectID) == ["a", "c"])
        #expect(results.map(\.subjectTitle) == ["Housing affordability", "Affordable housing starts"])
    }

    @Test func ignoresQueriesShorterThanTwoCharacters() {
        let useCase = SearchHansard(store: StubHansardSearchStore(documents: [
            HansardSearchDocument(subjectID: "a", subjectTitle: "Housing affordability", hansardDate: .now)
        ]))

        #expect(useCase.execute(query: "h").isEmpty)
        #expect(useCase.execute(query: " ").isEmpty)
    }

    @Test func cachingStoreLoadsBaseDocumentsOnlyOnce() throws {
        let base = CountingHansardSearchStore(documents: [
            HansardSearchDocument(subjectID: "a", subjectTitle: "Housing affordability", hansardDate: .now)
        ])
        let store = CachingHansardSearchStore(base: base)

        let first = try store.loadDocuments()
        let second = try store.loadDocuments()

        #expect(first == second)
        #expect(base.loadCount == 1)
    }
}

private struct StubHansardSearchStore: HansardSearchStore {
    let documents: [HansardSearchDocument]

    func loadDocuments() throws -> [HansardSearchDocument] {
        documents
    }
}

@MainActor
private final class CountingHansardSearchStore: HansardSearchStore {
    let documents: [HansardSearchDocument]
    private(set) var loadCount = 0

    init(documents: [HansardSearchDocument]) {
        self.documents = documents
    }

    func loadDocuments() throws -> [HansardSearchDocument] {
        loadCount += 1
        return documents
    }
}
