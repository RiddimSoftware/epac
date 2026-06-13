//
//  NotifyFollowedBillRoyalAssentTests.swift
//  epacTests
//

@testable import epac
import XCTest

@MainActor
final class NotifyFollowedBillRoyalAssentTests: XCTestCase {
    func testSendsNotificationWithFormattedBody() async throws {
        let port = MockRoyalAssentNotificationPort()
        let useCase = NotifyFollowedBillRoyalAssent(notificationPort: port)

        let bill = Bill(
            id: "C-226",
            number: "C-226",
            title: "National Framework for Food Price Transparency Act",
            sponsorName: "Jane Smith",
            status: .royalAssent,
            currentStage: "Royal Assent",
            introducedDate: nil,
            royalAssentDate: nil,
            summary: nil,
            sponsorProfileURL: nil,
            stages: [],
            legisInfoURL: URL(string: "https://www.parl.ca")!,
            type: .government,
            parliament: 45,
            session: 1
        )

        try await useCase.execute(bill: bill)

        XCTAssertEqual(port.sentNotifications.count, 1)
        let sent = port.sentNotifications.first
        XCTAssertEqual(sent?.title, "C-226")
        XCTAssertEqual(sent?.body, "National Framework for Food Price Transparency Act received Royal Assent today and is now law.")
    }
}

@MainActor
private final class MockRoyalAssentNotificationPort: RoyalAssentNotificationPort {
    var sentNotifications: [RoyalAssentNotification] = []

    func sendNotification(_ notification: RoyalAssentNotification) async throws {
        sentNotifications.append(notification)
    }
}
