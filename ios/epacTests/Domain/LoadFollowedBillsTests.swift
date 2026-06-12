//
//  LoadFollowedBillsTests.swift
//  epacTests
//

@testable import epac
import XCTest

@MainActor
final class LoadFollowedBillsTests: XCTestCase {

    func testExecuteWithNoFollowedBills() async throws {
        let followedPort = MockFollowedBillReadPort(records: [])
        let statusPort = MockBillStatusReadPort(bills: [])
        let useCase = LoadFollowedBills(followedBillReadPort: followedPort, billStatusReadPort: statusPort)

        let result = try await useCase.execute()
        XCTAssertTrue(result.isEmpty)
    }

    func testExecuteWithFollowedBillsMatchingFreshBills() async throws {
        let now = Date()
        let record = FollowedBillRecord(
            number: "C-11",
            lastKnownStatus: "InProgress",
            lastKnownStage: "Second Reading",
            followedAt: now,
            hasUnreadUpdate: true
        )
        let bill = Bill(
            id: "C-11",
            number: "C-11",
            title: "Online Streaming Act",
            sponsorName: "Minister of Heritage",
            status: .inProgress,
            currentStage: "Third Reading",
            introducedDate: now,
            stages: [],
            legisInfoURL: URL(string: "https://parl.ca")!,
            type: .government,
            parliament: 44,
            session: 1
        )

        let followedPort = MockFollowedBillReadPort(records: [record])
        let statusPort = MockBillStatusReadPort(bills: [bill])
        let useCase = LoadFollowedBills(followedBillReadPort: followedPort, billStatusReadPort: statusPort)

        let result = try await useCase.execute()
        XCTAssertEqual(result.count, 1)
        let first = result[0]
        XCTAssertEqual(first.number, "C-11")
        XCTAssertEqual(first.title, "Online Streaming Act")
        XCTAssertEqual(first.status, .inProgress)
        XCTAssertEqual(first.currentStage, "Third Reading")
        XCTAssertEqual(first.hasUnreadUpdate, true)
        XCTAssertNotNil(first.bill)
    }

    func testExecuteWithFollowedBillNotMatchingFreshBills() async throws {
        let now = Date()
        let record = FollowedBillRecord(
            number: "C-12",
            lastKnownStatus: "RoyalAssent",
            lastKnownStage: "Royal Assent",
            followedAt: now,
            hasUnreadUpdate: false
        )

        let followedPort = MockFollowedBillReadPort(records: [record])
        let statusPort = MockBillStatusReadPort(bills: [])
        let useCase = LoadFollowedBills(followedBillReadPort: followedPort, billStatusReadPort: statusPort)

        let result = try await useCase.execute()
        XCTAssertEqual(result.count, 1)
        let first = result[0]
        XCTAssertEqual(first.number, "C-12")
        XCTAssertEqual(first.title, "C-12") // Fallback title
        XCTAssertEqual(first.status, .royalAssent)
        XCTAssertEqual(first.currentStage, "Royal Assent")
        XCTAssertEqual(first.hasUnreadUpdate, false)
        XCTAssertNil(first.bill)
    }
}

@MainActor
class MockFollowedBillReadPort: FollowedBillReadPort {
    let records: [FollowedBillRecord]

    init(records: [FollowedBillRecord]) {
        self.records = records
    }

    func fetchFollowedBills() async throws -> [FollowedBillRecord] {
        return records
    }
}

@MainActor
class MockBillStatusReadPort: BillStatusReadPort {
    let bills: [Bill]

    init(bills: [Bill]) {
        self.bills = bills
    }

    func fetchBills() async throws -> [Bill] {
        return bills
    }
}
