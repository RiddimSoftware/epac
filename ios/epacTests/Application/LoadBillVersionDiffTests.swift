@testable import epac
import Foundation
import Testing

struct LoadBillVersionDiffTests {
    @Test func executeReturnsDiffFromRepository() async throws {
        let diff = Self.sampleDiff()
        let repository = StubBillVersionDiffRepository(diff: diff)
        let useCase = LoadBillVersionDiff(repository: repository)

        let result = try await useCase.execute(
            billID: "C-8",
            fromVersionID: "C-8-v1",
            toVersionID: "C-8-v3"
        )

        #expect(repository.requests == [StubBillVersionDiffRepository.Request(
            billID: "C-8",
            fromVersionID: "C-8-v1",
            toVersionID: "C-8-v3"
        )])
        #expect(result == diff)
    }

    @Test func executeReturnsNilWhenRepositoryHasNoDiff() async throws {
        let repository = StubBillVersionDiffRepository(diff: nil)
        let useCase = LoadBillVersionDiff(repository: repository)

        let result = try await useCase.execute(
            billID: "C-9",
            fromVersionID: "v1",
            toVersionID: "v2"
        )

        #expect(result == nil)
    }

    @Test func executePropagatesRepositoryErrors() async {
        let repository = StubBillVersionDiffRepository(error: StubBillVersionDiffRepositoryError.failed)
        let useCase = LoadBillVersionDiff(repository: repository)

        await #expect(throws: StubBillVersionDiffRepositoryError.failed) {
            _ = try await useCase.execute(billID: "C-9", fromVersionID: "v1", toVersionID: "v2")
        }
    }

    private static func sampleDiff() -> BillVersionDiff {
        BillVersionDiff(
            fromVersion: BillVersion(
                id: "C-8-v1",
                label: "First reading",
                title: nil,
                stage: "First Reading",
                chamber: "House of Commons",
                publishedOn: nil,
                sourceURL: nil
            ),
            toVersion: BillVersion(
                id: "C-8-v3",
                label: "As passed by the House",
                title: nil,
                stage: "Third Reading",
                chamber: "House of Commons",
                publishedOn: nil,
                sourceURL: nil
            ),
            clauseDiffs: [
                BillClauseDiff(
                    id: "clause-3",
                    label: "Clause 3",
                    changeType: .added,
                    fromText: "",
                    toText: "The Minister shall publish quarterly progress reports.",
                    hansardAnchorURL: nil
                )
            ]
        )
    }
}

private enum StubBillVersionDiffRepositoryError: Error {
    case failed
}

private final class StubBillVersionDiffRepository: BillVersionDiffRepository, @unchecked Sendable {
    struct Request: Equatable, Sendable {
        let billID: String
        let fromVersionID: String
        let toVersionID: String
    }

    private let diff: BillVersionDiff?
    private let error: Error?
    private(set) var requests: [Request] = []

    init(diff: BillVersionDiff? = nil, error: Error? = nil) {
        self.diff = diff
        self.error = error
    }

    func loadBillVersionDiff(
        billID: String,
        fromVersionID: String,
        toVersionID: String
    ) async throws -> BillVersionDiff? {
        requests.append(Request(
            billID: billID,
            fromVersionID: fromVersionID,
            toVersionID: toVersionID
        ))
        if let error {
            throw error
        }
        return diff
    }
}
