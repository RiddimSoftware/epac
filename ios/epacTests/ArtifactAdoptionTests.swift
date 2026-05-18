@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
struct ArtifactAdoptionTests {
    @Test func billsServiceReadsBillsArtifact() async throws {
        let artifacts = MockArtifactFetcher([.billsAll: """
        {
          "bills": [
            {
              "id": "C-5",
              "number": "C-5",
              "title": "An Act respecting tests",
              "sponsor_name": "Jane Example",
              "status": "InProgress",
              "current_stage": "Second Reading",
              "introduced_on": "2026-04-29",
              "stages": [
                {
                  "id": "C-5-h1",
                  "name": "House First Reading",
                  "completed_date": "2026-04-29",
                  "is_completed": true
                }
              ],
              "bill_type": "HouseGovernment",
              "parliament": 45,
              "session": 1,
              "legis_info_url": "https://www.parl.ca/legisinfo/en/bill/45-1/c-5"
            }
          ]
        }
        """])

        let bills = try await BillsService.fetchBills(artifacts: artifacts)

        #expect(bills.map(\.number) == ["C-5"])
        #expect(bills.first?.status == .inProgress)
        #expect(bills.first?.stages.first?.isCompleted == true)
        #expect(artifacts.requestedKeys == [.billsAll])
    }

    @Test func fetchDownloadsMembersFromArtifactAndIngestsSwiftData() async throws {
        let container = try makeContainer()
        let fetch = Fetch(modelContainer: container)
        let artifacts = MockArtifactFetcher([.membersAll: """
        {
          "members": [
            {
              "id": "278707",
              "name": "Jane Example",
              "riding": "Ottawa Centre",
              "province": "ON",
              "party": "Liberal"
            }
          ]
        }
        """])

        try await fetch.downloadMembers(artifacts: artifacts)

        let members = try container.mainContext.fetch(FetchDescriptor<ParliamentMember>())
        #expect(members.map(\.memberID) == [278707])
        #expect(members.first?.riding == "Ottawa Centre")
        #expect(artifacts.requestedKeys == [.membersAll])
    }

    @Test func fetchDownloadsSittingCalendarFromArtifactAndIngestsSwiftData() async throws {
        let container = try makeContainer()
        let fetch = Fetch(modelContainer: container)
        let artifacts = MockArtifactFetcher([.sittingsAll: """
        {
          "page": 1,
          "per_page": 1,
          "total": 1,
          "sittings": [
            {
              "date": "2026-04-29",
              "parliament_num": 45,
              "session_num": 1,
              "source_url": "https://www.ourcommons.ca/"
            }
          ]
        }
        """])

        let dates = try await fetch.downloadCalendar(year: 2026, artifacts: artifacts)

        let calendars = try container.mainContext.fetch(FetchDescriptor<SittingCalendar>())
        #expect(dates.count == 1)
        #expect(calendars.first?.sittings.count == 1)
        #expect(artifacts.requestedKeys == [.sittingsAll])
    }

    @Test func fetchDownloadsHansardFromSittingSpeechArtifactAndIngestsSwiftData() async throws {
        let container = try makeContainer()
        let fetch = Fetch(modelContainer: container)
        let key = ArtifactKey("sittings/v1/by-date/2026-04-29.json")
        let artifacts = MockArtifactFetcher([key: """
        {
          "date": "2026-04-29",
          "page": 1,
          "per_page": 1,
          "total": 1,
          "speeches": [
            {
              "id": "int-1",
              "speaker_name": "Jane Example",
              "member_id": "278707",
              "parliament_num": 45,
              "session_num": 1,
              "subject_title": "Housing",
              "content": "Madam Speaker, housing affordability matters.",
              "source_url": "https://www.ourcommons.ca/"
            }
          ]
        }
        """])

        try await fetch.downloadHansard(date(2026, 4, 29), artifacts: artifacts)

        let hansards = try container.mainContext.fetch(FetchDescriptor<Hansard>())
        #expect(hansards.count == 1)
        #expect(hansards.first?.orders.first?.subjects.first?.title == "Housing")
        #expect(hansards.first?.orders.first?.subjects.first?.speeches.first?.messages.first?.content == "Madam Speaker, housing affordability matters.")
        #expect(artifacts.requestedKeys == [key])
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(SchemaV8.models), configurations: config)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/Toronto")
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
