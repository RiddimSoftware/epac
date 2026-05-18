@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct RuntimeDataPathTests {
    @Test func fetchDownloadsCalendarFromOurCommons() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://www.ourcommons.ca/en/sitting-calendar/2026")
            let html = """
            <html><body>
                <table>
                    <tr><td class="calendar-day chamber-meeting 2026-04-29">29</td></tr>
                    <tr><td class="calendar-day chamber-meeting 2026-05-12">12</td></tr>
                </table>
            </body></html>
            """
            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let container = try makeContainer()
        let fetch = Fetch(modelContainer: container)

        let dates = try await fetch.downloadCalendar(year: 2026)

        #expect(dates.count == 2)
    }

    @Test func fetchDownloadsMembersFromOurCommonsXML() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://www.ourcommons.ca/Members/en/search/XML?parliament=all&caucusId=all&province=all&gender=all")
            let xml = """
            <ArrayOfMemberOfParliament>
                <MemberOfParliament>
                    <PersonId>278707</PersonId>
                    <PersonOfficialFirstName>Jane</PersonOfficialFirstName>
                    <PersonOfficialLastName>Example</PersonOfficialLastName>
                    <ConstituencyName>Ottawa Centre</ConstituencyName>
                    <ConstituencyProvinceTerritoryName>Ontario</ConstituencyProvinceTerritoryName>
                    <CaucusShortName>Lib.</CaucusShortName>
                    <FromDateTime>2025-04-29T00:00:00</FromDateTime>
                </MemberOfParliament>
            </ArrayOfMemberOfParliament>
            """
            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(xml.utf8)
            )
        }

        let container = try makeContainer()
        let fetch = Fetch(modelContainer: container)

        try await fetch.downloadMembers()

        let members = try container.mainContext.fetch(FetchDescriptor<ParliamentMember>())
        #expect(members.map(\.memberID) == [278707])
        #expect(members.first?.riding == "Ottawa Centre")
    }

    @Test func ridingBoundaryServiceUsesBackendAPI() async throws {
        let harness = try makeNetworkHarness()
        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/api/v1/ridings/spadina-harbourfront/boundary")
            let json = """
            {
              "slug": "spadina-harbourfront",
              "name": "Spadina-Harbourfront",
              "external_id": "35100",
              "representation_order": "2023",
              "source": "Elections Canada",
              "source_url": "https://www.elections.ca/",
              "source_note": "Boundary geometry source note.",
              "extent": [-79.41, 43.62, -79.36, 43.66],
              "centroid": [-79.39, 43.64],
              "geometry": {
                "type": "Polygon",
                "coordinates": [[[-79.41,43.62],[-79.40,43.63],[-79.36,43.66],[-79.41,43.62]]]
              }
            }
            """
            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let service = RidingBoundaryService(
            baseURL: URL(string: "https://api.example.test")!,
            network: harness.service
        )

        let boundary = try await service.boundary(for: "Spadina-Harbourfront")

        #expect(boundary.slug == "spadina-harbourfront")
    }

    @Test func billsServiceUsesLEGISinfoEndpoint() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://www.parl.ca/legisinfo/en/bills/json?parlsession=45-1&load=yes")
            let json = """
            [
              {
                "BillNumberFormatted": "C-5",
                "ShortTitleEn": "An Act respecting tests",
                "LongTitleEn": null,
                "LatestCompletedMajorStageEn": "Second Reading",
                "CurrentStatusEn": "In progress",
                "BillTypeEn": "House Government Bill",
                "SponsorEn": "Jane Example",
                "OriginatingChamberId": 1,
                "ParliamentNumber": 45,
                "SessionNumber": 1,
                "PassedHouseFirstReadingDateTime": "2026-04-29T08:00:00-04:00",
                "PassedHouseSecondReadingDateTime": null,
                "PassedHouseThirdReadingDateTime": null,
                "PassedSenateFirstReadingDateTime": null,
                "PassedSenateSecondReadingDateTime": null,
                "PassedSenateThirdReadingDateTime": null,
                "ReceivedRoyalAssentDateTime": null
              }
            ]
            """
            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let bills = try await BillsService.fetchBills()

        #expect(bills.map(\.number) == ["C-5"])
        #expect(bills.first?.status == .inProgress)
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(SchemaV8.models), configurations: config)
    }

    private func makeNetworkHarness() throws -> NetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let suiteName = "RuntimeDataPathTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeDataPathTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
        return NetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            suiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }
}

private struct NetworkHarness {
    let service: NetworkService
    let suiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw URLError(.unknown)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
