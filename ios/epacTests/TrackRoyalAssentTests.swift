//
//  TrackRoyalAssentTests.swift
//  epacTests
//

@testable import epac
import XCTest

@MainActor
final class TrackRoyalAssentTests: XCTestCase {
    func testRecentlyBecameLawFiltersToLastThirtyDaysAndSortsMostRecentFirst() async throws {
        let repository = RoyalAssentBillRepository(bills: [
            Self.bill(number: "C-10", status: .royalAssent, royalAssentDate: Self.date("2026-06-10")),
            Self.bill(number: "C-11", status: .royalAssent, royalAssentDate: Self.date("2026-05-20")),
            Self.bill(number: "C-12", status: .royalAssent, royalAssentDate: Self.date("2026-04-30")),
            Self.bill(number: "C-13", status: .inProgress, royalAssentDate: nil),
            Self.bill(number: "S-1", status: .royalAssent, royalAssentDate: Self.date("2026-06-12"))
        ])
        let useCase = TrackRoyalAssent(
            repository: repository,
            clock: RoyalAssentClock(now: Self.date("2026-06-12")),
            calendar: Self.calendar
        )

        let bills = try await useCase.recentlyBecameLaw()

        XCTAssertEqual(bills.map(\.number), ["S-1", "C-10", "C-11"])
    }

    private static func bill(number: String, status: BillStatus, royalAssentDate: Date?) -> Bill {
        Bill(
            id: number,
            number: number,
            title: "An Act respecting \(number)",
            sponsorName: "Jane Smith",
            status: status,
            currentStage: status == .royalAssent ? "Royal Assent" : "Second Reading",
            introducedDate: nil,
            royalAssentDate: royalAssentDate,
            summary: "Long title for \(number).",
            sponsorProfileURL: nil,
            stages: [],
            legisInfoURL: URL(string: "https://www.parl.ca/legisinfo/en/bill/45-1/\(number.lowercased())")!,
            type: .government,
            parliament: 45,
            session: 1
        )
    }

    private static func date(_ value: String) -> Date {
        dateFormatter.date(from: value)!
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

@MainActor
private struct RoyalAssentBillRepository: BillRepository {
    let bills: [Bill]

    func fetchBills() async throws -> [Bill] {
        bills
    }
}

private struct RoyalAssentClock: Clock {
    let now: Date
}
