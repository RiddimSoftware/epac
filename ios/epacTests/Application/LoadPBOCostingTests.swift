@testable import epac
import Foundation
import Testing

struct LoadPBOCostingTests {
    @Test func executeReturnsNilWhenPortHasNoRecord() async throws {
        let port = StubPBOCostingQueryPort(costings: nil)
        let useCase = LoadPBOCosting(queryPort: port)

        let result = try await useCase.execute(billID: "C-20")

        #expect(port.requestedBillIDs == ["C-20"])
        #expect(result == nil)
    }

    @Test func executeReturnsNilWhenPortHasEmptyArray() async throws {
        let port = StubPBOCostingQueryPort(costings: [])
        let useCase = LoadPBOCosting(queryPort: port)

        let result = try await useCase.execute(billID: "C-21")

        #expect(port.requestedBillIDs == ["C-21"])
        #expect(result == nil)
    }

    @Test func executeReturnsSingleNoteAsLatestWithNoOtherReports() async throws {
        let note = Self.costing(id: "PBO-1", published: "2026-05-01")
        let port = StubPBOCostingQueryPort(costings: [note])
        let useCase = LoadPBOCosting(queryPort: port)

        let result = try #require(try await useCase.execute(billID: "C-22"))

        #expect(result.latest == note)
        #expect(result.otherReports.isEmpty)
    }

    @Test func executePicksLatestByPublicationDateAndLinksOlderNotes() async throws {
        let oldest = Self.costing(id: "PBO-old", published: "2025-11-15")
        let middle = Self.costing(id: "PBO-mid", published: "2026-02-20")
        let newest = Self.costing(id: "PBO-new", published: "2026-06-01")
        // Deliberately unsorted input so the use case must sort.
        let port = StubPBOCostingQueryPort(costings: [middle, oldest, newest])
        let useCase = LoadPBOCosting(queryPort: port)

        let result = try #require(try await useCase.execute(billID: "C-23"))

        #expect(result.latest == newest)
        #expect(result.otherReports == [middle, oldest])
    }

    @Test func executeSortsNotesWithoutDatesLast() async throws {
        let dated = Self.costing(id: "PBO-dated", published: "2026-03-10")
        let undated = Self.costing(id: "PBO-undated", published: nil)
        let port = StubPBOCostingQueryPort(costings: [undated, dated])
        let useCase = LoadPBOCosting(queryPort: port)

        let result = try #require(try await useCase.execute(billID: "C-24"))

        #expect(result.latest == dated)
        #expect(result.otherReports == [undated])
    }

    @Test func executeBreaksDateTiesDeterministicallyByID() async throws {
        let sameDayB = Self.costing(id: "PBO-b", published: "2026-04-04")
        let sameDayA = Self.costing(id: "PBO-a", published: "2026-04-04")
        let port = StubPBOCostingQueryPort(costings: [sameDayB, sameDayA])
        let useCase = LoadPBOCosting(queryPort: port)

        let result = try #require(try await useCase.execute(billID: "C-25"))

        // Equal dates fall back to ascending id, so "PBO-a" wins deterministically.
        #expect(result.latest == sameDayA)
        #expect(result.otherReports == [sameDayB])
    }

    @Test func executePropagatesPortErrors() async {
        let port = StubPBOCostingQueryPort(error: StubPBOCostingQueryPortError.failed)
        let useCase = LoadPBOCosting(queryPort: port)

        await #expect(throws: StubPBOCostingQueryPortError.failed) {
            _ = try await useCase.execute(billID: "C-26")
        }
    }

    private static func costing(
        id: String,
        published: String?
    ) -> PBOCosting {
        PBOCosting(
            id: id,
            title: "Cost estimate for \(id)",
            headlineFigureMillions: "1,240",
            methodologyCategory: "legislative-cost",
            publishedAt: published.flatMap(Self.date(_:)),
            reportURL: URL(string: "https://www.pbo-dpb.ca/reports/\(id).pdf")!,
            sourceURL: URL(string: "https://www.pbo-dpb.ca/reports/\(id)"),
            summaryText: "Verbatim PBO summary for \(id)."
        )
    }

    private static func date(_ rawValue: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawValue) ?? Date(timeIntervalSince1970: 0)
    }
}

private enum StubPBOCostingQueryPortError: Error {
    case failed
}

private final class StubPBOCostingQueryPort: PBOCostingQueryPort, @unchecked Sendable {
    private let costings: [PBOCosting]?
    private let error: Error?
    private(set) var requestedBillIDs: [String] = []

    init(costings: [PBOCosting]? = nil, error: Error? = nil) {
        self.costings = costings
        self.error = error
    }

    func loadPBOCostings(billID: String) async throws -> [PBOCosting]? {
        requestedBillIDs.append(billID)
        if let error {
            throw error
        }
        return costings
    }
}
