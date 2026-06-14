@testable import epac
import Foundation
import Testing

struct LoadBillAmendmentsTests {
    @Test func executeReturnsAmendmentsFromRepository() async throws {
        let amendments = Self.sampleAmendments()
        let repository = StubBillAmendmentsRepository(amendments: amendments)
        let useCase = LoadBillAmendments(repository: repository)

        let result = try await useCase.execute(billID: "C-8")

        #expect(repository.requestedBillIDs == ["C-8"])
        #expect(result == amendments)
    }

    @Test func executeReturnsEmptyArrayWhenRepositoryHasNoAmendmentsForBill() async throws {
        let repository = StubBillAmendmentsRepository(amendments: [])
        let useCase = LoadBillAmendments(repository: repository)

        let result = try await useCase.execute(billID: "C-9")

        #expect(repository.requestedBillIDs == ["C-9"])
        #expect(result == [])
    }

    @Test func executeReturnsNilWhenRepositoryHasNoAmendmentsRecord() async throws {
        let repository = StubBillAmendmentsRepository(amendments: nil)
        let useCase = LoadBillAmendments(repository: repository)

        let result = try await useCase.execute(billID: "C-10")

        #expect(repository.requestedBillIDs == ["C-10"])
        #expect(result == nil)
    }

    @Test func executePropagatesRepositoryErrors() async {
        let repository = StubBillAmendmentsRepository(error: StubBillAmendmentsRepositoryError.failed)
        let useCase = LoadBillAmendments(repository: repository)

        await #expect(throws: StubBillAmendmentsRepositoryError.failed) {
            _ = try await useCase.execute(billID: "C-11")
        }
    }

    private static func sampleAmendments() -> [BillAmendment] {
        [
            BillAmendment(
                id: "C-8-a-1",
                number: "LIB-1",
                title: "Clause 5: replace subsection (2)",
                sponsorName: "Hon. Member A",
                proposedOn: Date(timeIntervalSince1970: 1_780_704_000),
                stage: "Committee",
                status: .passed,
                statusLabel: "adopted",
                text: "That Bill C-8, in Clause 5, be amended by replacing line 10 on page 3 with the following: ...",
                sourceURL: URL(string: "https://www.parl.ca/legisinfo/amendment/1")
            )
        ]
    }
}

private enum StubBillAmendmentsRepositoryError: Error {
    case failed
}

private final class StubBillAmendmentsRepository: BillAmendmentsRepository, @unchecked Sendable {
    private let amendments: [BillAmendment]?
    private let error: Error?
    private(set) var requestedBillIDs: [String] = []

    init(amendments: [BillAmendment]? = nil, error: Error? = nil) {
        self.amendments = amendments
        self.error = error
    }

    func loadBillAmendments(billID: String) async throws -> [BillAmendment]? {
        requestedBillIDs.append(billID)
        if let error {
            throw error
        }
        return amendments
    }
}
