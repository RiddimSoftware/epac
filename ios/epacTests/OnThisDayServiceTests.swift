@testable import epac
import XCTest

final class OnThisDayServiceTests: XCTestCase {
    func testDecodesSpeechItem() throws {
        let payload = """
        {
          "items": [
            {
              "id": "speech:12345",
              "kind": "speech",
              "year": 2021,
              "date": "2021-04-29",
              "title": "Housing",
              "excerpt": "Madam Speaker, housing affordability matters.",
              "speaker_name": "Jane Example",
              "member_id": "278707",
              "subject_title": "Housing",
              "intervention_id": "12345",
              "source_url": "https://www.ourcommons.ca/documentviewer/en/44-1/house/sitting-1/hansard"
            }
          ]
        }
        """
        let json = Data(payload.utf8)

        let response = try JSONDecoder().decode(OnThisDayResponse.self, from: json)

        XCTAssertNil(response.date)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items[0].kind, .speech)
        XCTAssertEqual(response.items[0].detailText, "2021 · Jane Example")
        XCTAssertEqual(response.items[0].parsedDate, onThisDayTestDate(2021, 4, 29))
    }

    func testDetailFallsBackToYearWhenSpeakerMissing() throws {
        let item = OnThisDayItem(
            id: "speech:1",
            kind: .speech,
            year: 2009,
            date: "2009-04-29",
            title: "Budget",
            excerpt: "Budget text",
            speakerName: nil,
            memberID: nil,
            subjectTitle: nil,
            interventionID: nil,
            voteID: nil,
            billNumber: nil,
            sourceURL: nil
        )

        XCTAssertEqual(item.detailText, "2009")
    }

    func testBuildsArtifactKey() throws {
        let key = OnThisDayService().artifactKey(date: onThisDayTestDate(2026, 4, 29)!)

        XCTAssertEqual(key, .onThisDayAll)
    }

    func testFetchReadsPublishedArtifactAndAppliesBackendFiltering() async throws {
        let payload = """
        {
          "items": [
            {
              "id": "speech:1",
              "kind": "speech",
              "year": 2021,
              "date": "2021-04-29",
              "title": "Housing",
              "excerpt": "One",
              "speaker_name": "Jane Example"
            },
            {
              "id": "speech:2",
              "kind": "speech",
              "year": 2020,
              "date": "2020-04-29",
              "title": "Health",
              "excerpt": "Two"
            },
            {
              "id": "speech:same-year",
              "kind": "speech",
              "year": 2026,
              "date": "2026-04-29",
              "title": "Current year",
              "excerpt": "Exclude non-past dates."
            },
            {
              "id": "speech:wrong-day",
              "kind": "speech",
              "year": 2019,
              "date": "2019-04-30",
              "title": "Wrong day",
              "excerpt": "Exclude another calendar day."
            }
          ]
        }
        """
        let artifacts = MockArtifactFetcher([.onThisDayAll: payload])

        let items = try await OnThisDayService(artifacts: artifacts).fetch(
            date: onThisDayTestDate(2026, 4, 29)!,
            limit: 10
        )

        XCTAssertEqual(items.map(\.id), ["speech:1", "speech:2"])
        XCTAssertEqual(artifacts.requestedKeys, [.onThisDayAll])
    }

    func testFetchCapsPublishedArtifactResultsToLimit() async throws {
        let payload = """
        {
          "items": [
            {
              "id": "speech:1",
              "kind": "speech",
              "year": 2021,
              "date": "2021-04-29",
              "title": "Housing",
              "excerpt": "One"
            },
            {
              "id": "speech:2",
              "kind": "speech",
              "year": 2020,
              "date": "2020-04-29",
              "title": "Health",
              "excerpt": "Two"
            }
          ]
        }
        """
        let artifacts = MockArtifactFetcher([.onThisDayAll: payload])

        let items = try await OnThisDayService(artifacts: artifacts).fetch(
            date: onThisDayTestDate(2026, 4, 29)!,
            limit: 1
        )

        XCTAssertEqual(items.map(\.id), ["speech:1"])
        XCTAssertEqual(artifacts.requestedKeys, [.onThisDayAll])
    }

    private func onThisDayTestDate(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/Toronto")
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }
}
