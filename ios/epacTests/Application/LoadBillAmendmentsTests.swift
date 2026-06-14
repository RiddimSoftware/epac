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

    @Test func executeReturnsEmptyArrayWhenNoAmendmentsTabled() async throws {
        let repository = StubBillAmendmentsRepository(amendments: [])
        let useCase = LoadBillAmendments(repository: repository)

        let result = try await useCase.execute(billID: "C-9")

        #expect(repository.requestedBillIDs == ["C-9"])
        #expect(result.isEmpty)
    }

    @Test func executePropagatesRepositoryErrors() async {
        let repository = StubBillAmendmentsRepository(error: StubBillAmendmentsRepositoryError.failed)
        let useCase = LoadBillAmendments(repository: repository)

        await #expect(throws: StubBillAmendmentsRepositoryError.failed) {
            _ = try await useCase.execute(billID: "C-10")
        }
    }

    @Test func statusInitMapsKnownBackendValues() {
        #expect(BillAmendmentStatus(backendValue: "passed") == .passed)
        #expect(BillAmendmentStatus(backendValue: "Adopted") == .passed)
        #expect(BillAmendmentStatus(backendValue: "agreed to") == .passed)
        #expect(BillAmendmentStatus(backendValue: "carried") == .passed)
        #expect(BillAmendmentStatus(backendValue: "DEFEATED") == .defeated)
        #expect(BillAmendmentStatus(backendValue: "negatived") == .defeated)
        #expect(BillAmendmentStatus(backendValue: "rejected") == .defeated)
        #expect(BillAmendmentStatus(backendValue: "withdrawn") == .withdrawn)
        #expect(BillAmendmentStatus(backendValue: " WITHDRAWN ") == .withdrawn)
    }

    @Test func statusInitFallsBackToOtherForUnknownValues() {
        #expect(BillAmendmentStatus(backendValue: "") == .other)
        #expect(BillAmendmentStatus(backendValue: "in deliberation") == .other)
        #expect(BillAmendmentStatus(backendValue: "queued") == .other)
    }

    private static func sampleAmendments() -> [BillAmendment] {
        [
            BillAmendment(
                id: "C-8-a1",
                number: "LIB-1",
                clauseReference: "Clause 12, subsection (2)",
                status: .passed,
                rawStatus: "passed",
                stage: "Committee",
                moverName: "Jane Doe",
                proposedOn: Date(timeIntervalSince1970: 1_780_444_800),
                text: "That Clause 12 be amended by adding the following after line 14: ...",
                sourceURL: URL(string: "https://www.parl.ca/amendment/C-8-a1")
            )
        ]
    }
}

private enum StubBillAmendmentsRepositoryError: Error {
    case failed
}

private final class StubBillAmendmentsRepository: BillAmendmentsRepository, @unchecked Sendable {
    private let amendments: [BillAmendment]
    private let error: Error?
    private(set) var requestedBillIDs: [String] = []

    init(amendments: [BillAmendment] = [], error: Error? = nil) {
        self.amendments = amendments
        self.error = error
    }

    func loadBillAmendments(billID: String) async throws -> [BillAmendment] {
        requestedBillIDs.append(billID)
        if let error {
            throw error
        }
        return amendments
    }
}
