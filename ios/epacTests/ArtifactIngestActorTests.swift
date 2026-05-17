@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
struct ArtifactIngestActorTests {
    @Test func membersIngestIsIdempotentAndDiffsChanges() async throws {
        let container = try makeContainer()
        let actor = ArtifactIngestActor(modelContainer: container)

        let initial = MembersArtifact(members: [
            member(id: 1, riding: "Halifax", party: .liberal),
            member(id: 2, riding: "Calgary Centre", party: .conservative)
        ])

        let first = try await actor.ingestMembers(initial)
        #expect(first.inserted == 2)
        #expect(first.updated == 0)
        #expect(first.deleted == 0)

        let second = try await actor.ingestMembers(initial)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
        #expect(second.deleted == 0)

        let changed = MembersArtifact(members: [
            member(id: 1, riding: "Halifax West", party: .liberal),
            member(id: 2, riding: "Calgary Centre", party: .conservative)
        ])
        let update = try await actor.ingestMembers(changed)
        #expect(update.inserted == 0)
        #expect(update.updated == 1)
        #expect(update.deleted == 0)

        let removed = MembersArtifact(members: [
            member(id: 1, riding: "Halifax West", party: .liberal)
        ])
        let delete = try await actor.ingestMembers(removed)
        #expect(delete.inserted == 0)
        #expect(delete.updated == 0)
        #expect(delete.deleted == 1)

        let remaining = try container.mainContext.fetch(FetchDescriptor<ParliamentMember>())
        #expect(remaining.map(\.memberID) == [1])
        #expect(remaining.first?.riding == "Halifax West")
    }

    @Test func membersIngestClearsRemovedOptionalFields() async throws {
        let container = try makeContainer()
        let actor = ArtifactIngestActor(modelContainer: container)

        let initial = MembersArtifact(members: [
            member(
                id: 1,
                imageData: Data([1, 2, 3]),
                email: "member@example.ca",
                hillPhone: "613-555-0101",
                constituencyPhone: "902-555-0101",
                constituencyAddress: "1 Main Street",
                contactFetched: true
            )
        ])

        let first = try await actor.ingestMembers(initial)
        #expect(first.inserted == 1)

        let cleared = MembersArtifact(members: [
            member(id: 1)
        ])
        let update = try await actor.ingestMembers(cleared)
        #expect(update.inserted == 0)
        #expect(update.updated == 1)
        #expect(update.deleted == 0)

        let second = try await actor.ingestMembers(cleared)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
        #expect(second.deleted == 0)

        let stored = try #require(container.mainContext.fetch(FetchDescriptor<ParliamentMember>()).first)
        #expect(stored.imageData == nil)
        #expect(stored.email == nil)
        #expect(stored.hillPhone == nil)
        #expect(stored.constituencyPhone == nil)
        #expect(stored.constituencyAddress == nil)
        #expect(!stored.contactFetched)
    }

    @Test func sittingsIngestIsIdempotentAndDiffsDates() async throws {
        let container = try makeContainer()
        let actor = ArtifactIngestActor(modelContainer: container)
        let day1 = date(2026, 1, 27)
        let day2 = date(2026, 1, 28)
        let day3 = date(2026, 2, 3)

        let initial = SittingsArtifact(calendars: [
            SittingCalendarRecord(year: 2026, sittings: [day2, day1])
        ])

        let first = try await actor.ingestSittings(initial)
        #expect(first.inserted == 2)
        #expect(first.updated == 0)
        #expect(first.deleted == 0)

        let second = try await actor.ingestSittings(initial)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
        #expect(second.deleted == 0)

        let changed = SittingsArtifact(calendars: [
            SittingCalendarRecord(year: 2026, sittings: [day1, day3])
        ])
        let update = try await actor.ingestSittings(changed)
        #expect(update.inserted == 1)
        #expect(update.updated == 1)
        #expect(update.deleted == 1)

        let removed = SittingsArtifact(calendars: [])
        let delete = try await actor.ingestSittings(removed)
        #expect(delete.inserted == 0)
        #expect(delete.updated == 0)
        #expect(delete.deleted == 2)
        #expect(try container.mainContext.fetch(FetchDescriptor<SittingCalendar>()).isEmpty)
    }

    @Test func hansardSubjectsIngestIsIdempotentAndDiffsAggregates() async throws {
        let container = try makeContainer()
        let actor = ArtifactIngestActor(modelContainer: container)

        let firstPayload = HansardSubjectsArtifact(hansards: [
            hansard(id: "h-1", subjectID: "sub-1", subjectTitle: "Housing"),
            hansard(id: "h-2", subjectID: "sub-2", subjectTitle: "Health")
        ])

        let first = try await actor.ingestHansardSubjects(firstPayload)
        #expect(first.inserted == 2)
        #expect(first.updated == 0)
        #expect(first.deleted == 0)

        let second = try await actor.ingestHansardSubjects(firstPayload)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
        #expect(second.deleted == 0)

        let changedPayload = HansardSubjectsArtifact(hansards: [
            hansard(id: "h-1", subjectID: "sub-1", subjectTitle: "Housing affordability"),
            hansard(id: "h-2", subjectID: "sub-2", subjectTitle: "Health")
        ])
        let update = try await actor.ingestHansardSubjects(changedPayload)
        #expect(update.inserted == 0)
        #expect(update.updated == 1)
        #expect(update.deleted == 0)

        let removedPayload = HansardSubjectsArtifact(hansards: [
            hansard(id: "h-1", subjectID: "sub-1", subjectTitle: "Housing affordability")
        ])
        let delete = try await actor.ingestHansardSubjects(removedPayload)
        #expect(delete.inserted == 0)
        #expect(delete.updated == 0)
        #expect(delete.deleted == 1)

        let hansards = try container.mainContext.fetch(FetchDescriptor<Hansard>())
        #expect(hansards.count == 1)
        #expect(hansards.first?.orders.first?.subjects.first?.title == "Housing affordability")
    }

    @Test func billsIngestRejectsNonEmptyPayloadUntilBillsHaveSwiftDataModel() async throws {
        let container = try makeContainer()
        let actor = ArtifactIngestActor(modelContainer: container)

        let empty = try await actor.ingestBills(BillsArtifact(bills: []))
        #expect(empty.inserted == 0)
        #expect(empty.updated == 0)
        #expect(empty.deleted == 0)

        await #expect(throws: ArtifactIngestError.unsupportedBillPersistence(recordCount: 1)) {
            try await actor.ingestBills(BillsArtifact(bills: [
                Bill(
                    id: "C-1",
                    number: "C-1",
                    title: "An Act respecting tests",
                    sponsorName: "Jane Doe",
                    status: .inProgress,
                    currentStage: "First Reading",
                    introducedDate: nil,
                    stages: [],
                    legisInfoURL: URL(string: "https://example.com/bills/C-1")!,
                    billType: .houseGovernment,
                    parliament: 45,
                    session: 1
                )
            ]))
        }
    }

    @Test func mainRunLoopRemainsResponsiveDuringActorIngest() async throws {
        MainActor.assertIsolated()
        let container = try makeContainer()
        let actor = ArtifactIngestActor(modelContainer: container)
        let payload = MembersArtifact(members: (1...500).map { member(id: $0) })
        var runLoopAdvanced = false

        let ingest = Task {
            try await actor.ingestMembers(payload)
        }
        RunLoop.main.perform {
            runLoopAdvanced = true
        }
        pumpMainRunLoop()
        #expect(runLoopAdvanced)

        let result = try await ingest.value
        #expect(result.inserted == 500)
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(SchemaV8.models), configurations: config)
    }

    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func member(
        id: Int,
        riding: String? = nil,
        party: Party = .liberal,
        imageData: Data? = nil,
        email: String? = nil,
        hillPhone: String? = nil,
        constituencyPhone: String? = nil,
        constituencyAddress: String? = nil,
        contactFetched: Bool = false
    ) -> ParliamentMemberDTO {
        ParliamentMemberDTO(
            name: "Member \(id)",
            memberID: id,
            lastName: "Last\(id)",
            firstName: "First\(id)",
            photoURL: URL(string: "https://example.com/members/\(id).jpg")!,
            riding: riding ?? "Riding \(id)",
            province: .Ontario,
            party: party,
            websiteURL: nil,
            imageData: imageData,
            fromDateTime: nil,
            toDateTime: nil,
            email: email,
            hillPhone: hillPhone,
            constituencyPhone: constituencyPhone,
            constituencyAddress: constituencyAddress,
            contactFetched: contactFetched
        )
    }

    private func hansard(id: String, subjectID: String, subjectTitle: String) -> HansardDTO {
        let message = SpeechMessageDTO(
            firstName: "Jane",
            lastName: "Doe",
            partyAbbreviation: "Lib",
            ridingName: "Ottawa Centre",
            hansardID: "\(subjectID)-message-1",
            content: "Test speech text",
            timestamp: date(2026, 1, 27)
        )
        let speech = SpeechDTO(
            messages: [message],
            hansardID: "\(subjectID)-speech-1",
            currentMessageID: message.hansardID,
            date: date(2026, 1, 27),
            length: 1,
            title: subjectTitle
        )
        let subject = SubjectOfBusinessDTO(
            title: subjectTitle,
            hansardID: subjectID,
            speeches: [speech],
            currentSpeechID: speech.hansardID
        )
        let order = OrderOfBusinessDTO(
            hansardID: "\(id)-order-1",
            catchline: "Orders of the Day",
            subjects: [subject]
        )
        return HansardDTO(
            date: date(2026, 1, 27),
            hansardID: id,
            parliamentNumber: 45,
            sessionNumber: 1,
            orders: [order]
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
