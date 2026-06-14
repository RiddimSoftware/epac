@testable import epac
import Foundation
import Testing

struct LoadBillCommitteeStageTests {
    @Test func executeReturnsCommitteeStageFromRepository() async throws {
        let stage = Self.committeeStage()
        let repository = StubBillCommitteeStageRepository(stage: stage)
        let useCase = LoadBillCommitteeStage(repository: repository)

        let result = try await useCase.execute(billID: "C-8")

        #expect(repository.requestedBillIDs == ["C-8"])
        #expect(result == stage)
    }

    @Test func executeReturnsNilWhenRepositoryHasNoCurrentCommitteeStage() async throws {
        let repository = StubBillCommitteeStageRepository(stage: nil)
        let useCase = LoadBillCommitteeStage(repository: repository)

        let result = try await useCase.execute(billID: "C-9")

        #expect(repository.requestedBillIDs == ["C-9"])
        #expect(result == nil)
    }

    @Test func executePropagatesRepositoryErrors() async {
        let repository = StubBillCommitteeStageRepository(error: StubBillCommitteeStageRepositoryError.failed)
        let useCase = LoadBillCommitteeStage(repository: repository)

        await #expect(throws: StubBillCommitteeStageRepositoryError.failed) {
            _ = try await useCase.execute(billID: "C-10")
        }
    }

    private static func committeeStage() -> BillCommitteeStage {
        BillCommitteeStage(
            committee: ParliamentaryCommittee(
                id: "FINA",
                acronym: "FINA",
                name: "Standing Committee on Finance",
                chamberCode: "HOC",
                committeeURL: URL(string: "https://www.ourcommons.ca/Committees/en/FINA")!
            ),
            studiedSince: Date(timeIntervalSince1970: 1_780_444_800),
            studyCompletedAt: nil,
            upcomingMeetings: [],
            pastMeetings: []
        )
    }
}

private enum StubBillCommitteeStageRepositoryError: Error {
    case failed
}

private final class StubBillCommitteeStageRepository: BillCommitteeStageRepository, @unchecked Sendable {
    private let stage: BillCommitteeStage?
    private let error: Error?
    private(set) var requestedBillIDs: [String] = []

    init(stage: BillCommitteeStage? = nil, error: Error? = nil) {
        self.stage = stage
        self.error = error
    }

    func loadBillCommitteeStage(billID: String) async throws -> BillCommitteeStage? {
        requestedBillIDs.append(billID)
        if let error {
            throw error
        }
        return stage
    }
}
