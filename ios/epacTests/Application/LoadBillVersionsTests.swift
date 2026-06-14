@testable import epac
import Foundation
import Testing

struct LoadBillVersionsTests {
    @Test func executeReturnsVersionsFromRepository() async throws {
        let versions = Self.sampleVersions()
        let repository = StubBillVersionsRepository(versions: versions)
        let useCase = LoadBillVersions(repository: repository)

        let result = try await useCase.execute(billID: "C-8")

        #expect(repository.requestedBillIDs == ["C-8"])
        #expect(result == versions)
    }

    @Test func executeReturnsEmptyArrayWhenRepositoryHasNoVersionsForBill() async throws {
        let repository = StubBillVersionsRepository(versions: [])
        let useCase = LoadBillVersions(repository: repository)

        let result = try await useCase.execute(billID: "C-9")

        #expect(repository.requestedBillIDs == ["C-9"])
        #expect(result == [])
    }

    @Test func executeReturnsNilWhenRepositoryHasNoVersionsRecord() async throws {
        let repository = StubBillVersionsRepository(versions: nil)
        let useCase = LoadBillVersions(repository: repository)

        let result = try await useCase.execute(billID: "C-10")

        #expect(repository.requestedBillIDs == ["C-10"])
        #expect(result == nil)
    }

    @Test func executePropagatesRepositoryErrors() async {
        let repository = StubBillVersionsRepository(error: StubBillVersionsRepositoryError.failed)
        let useCase = LoadBillVersions(repository: repository)

        await #expect(throws: StubBillVersionsRepositoryError.failed) {
            _ = try await useCase.execute(billID: "C-11")
        }
    }

    private static func sampleVersions() -> [BillVersion] {
        [
            BillVersion(
                id: "C-8-v1",
                label: "First reading",
                title: nil,
                stage: "First Reading",
                chamber: "House of Commons",
                publishedOn: Date(timeIntervalSince1970: 1_777_910_400),
                sourceURL: URL(string: "https://www.parl.ca/legisinfo/bill/C-8/v1")
            ),
            BillVersion(
                id: "C-8-v3",
                label: "As passed by the House",
                title: nil,
                stage: "Third Reading",
                chamber: "House of Commons",
                publishedOn: Date(timeIntervalSince1970: 1_780_896_000),
                sourceURL: URL(string: "https://www.parl.ca/legisinfo/bill/C-8/v3")
            )
        ]
    }
}

private enum StubBillVersionsRepositoryError: Error {
    case failed
}

private final class StubBillVersionsRepository: BillVersionsRepository, @unchecked Sendable {
    private let versions: [BillVersion]?
    private let error: Error?
    private(set) var requestedBillIDs: [String] = []

    init(versions: [BillVersion]? = nil, error: Error? = nil) {
        self.versions = versions
        self.error = error
    }

    func loadBillVersions(billID: String) async throws -> [BillVersion]? {
        requestedBillIDs.append(billID)
        if let error {
            throw error
        }
        return versions
    }
}
