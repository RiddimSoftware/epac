@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct CabinetLobbyingRepositoryTests {
    @Test func ministerLobbyingDecodesBackendPortfolioResponse() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedURL: URL?

        CabinetLobbyingMockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.ministerPortfolioJSON()
            )
        }

        defer { harness.cleanup() }
        defer { CabinetLobbyingMockURLProtocol.requestHandler = nil }

        let repository = BackendCabinetLobbyingRepository(
            network: harness.service,
            baseURL: baseURL
        )

        let periods = try await repository.loadMinisterLobbyingByPortfolio(memberID: 314774)

        #expect(capturedURL?.path == "/api/v1/ministers/314774/lobbying-by-portfolio")
        #expect(periods.count == 1)
        #expect(periods[0].portfolioName == "Prime Minister of Canada")
        #expect(periods[0].startDate == expectedUTCDate(year: 2026, month: 4, day: 28))
        #expect(periods[0].endDate == nil)
        #expect(periods[0].communications.count == 1)
        #expect(periods[0].communications[0].organizationName == "Example Housing Association")
        #expect(periods[0].communications[0].lobbyistName == "Jane Registrant")
        #expect(periods[0].communications[0].subjectMatter == "Housing, Infrastructure")
        #expect(periods[0].communications[0].registrantType == "Consultant")
        #expect(periods[0].communications[0].communicationDate == expectedUTCDate(year: 2026, month: 5, day: 15))
        #expect(periods[0].communications[0].mandateMatch)
        #expect(periods[0].communications[0].registryURL == CabinetLobbyingSource.url)
    }

    @Test func cabinetOverviewSendsParliamentAndDerivesPortfolioOrganizations() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedURL: URL?

        CabinetLobbyingMockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.cabinetOverviewJSON()
            )
        }

        defer { harness.cleanup() }
        defer { CabinetLobbyingMockURLProtocol.requestHandler = nil }

        let repository = BackendCabinetLobbyingRepository(
            network: harness.service,
            baseURL: baseURL
        )

        let overview = try await repository.loadCabinetLobbyingOverview(parliament: 45)

        let requestURL = try #require(capturedURL)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/v1/cabinet/lobbying-overview")
        #expect(components.queryItems?.first(where: { $0.name == "parliament" })?.value == "45")
        #expect(overview.parliament == 45)
        #expect(overview.ministers.count == 1)
        #expect(overview.ministers[0].memberID == 314774)
        #expect(overview.ministers[0].ministerName == "Mark Carney")
        #expect(overview.ministers[0].portfolioName == "Prime Minister of Canada")
        #expect(overview.ministers[0].portfolioNames == ["Prime Minister of Canada"])
        #expect(overview.ministers[0].totalCommunications == 12)
        #expect(overview.portfolioFilters == ["Prime Minister of Canada"])
        #expect(overview.mostActiveOrganizations.count == 1)
        #expect(overview.mostActiveOrganizations[0].portfolioName == "Prime Minister of Canada")
        #expect(overview.mostActiveOrganizations[0].organizationName == "Example Housing Association")
        #expect(overview.mostActiveOrganizations[0].communicationCount == 3)
    }

    private func makeHarness() throws -> CabinetLobbyingNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CabinetLobbyingMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "CabinetLobbyingRepositoryTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CabinetLobbyingRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return CabinetLobbyingNetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }

    private func expectedUTCDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private static func ministerPortfolioJSON() -> Data {
        Data(
            """
            {
              "member_id": "314774",
              "minister_name": "Mark Carney",
              "total_communications": 1,
              "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
              "source_url": "https://lobbycanada.gc.ca/en/open-data/",
              "portfolios": [
                {
                  "portfolio_name": "Prime Minister of Canada",
                  "start_date": "2026-04-28",
                  "end_date": "",
                  "top_organizations": [
                    { "organization_name": "Example Housing Association", "count": 1 }
                  ],
                  "communications": [
                    {
                      "id": "558142",
                      "organization_name": "Example Housing Association",
                      "registrant_name": "Jane Registrant",
                      "registrant_type": "Consultant",
                      "communication_date": "2026-05-15",
                      "subject_matters": ["Housing", "Infrastructure"],
                      "ocl_codes": ["SMT-44"],
                      "mandate_match": true,
                      "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
                      "source_url": "https://lobbycanada.gc.ca/en/open-data/"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
    }

    private static func cabinetOverviewJSON() -> Data {
        Data(
            """
            {
              "parliament": 45,
              "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
              "source_url": "https://lobbycanada.gc.ca/en/open-data/",
              "ministers": [
                {
                  "member_id": "314774",
                  "minister_name": "Mark Carney",
                  "portfolios": [
                    {
                      "portfolio_name": "Prime Minister of Canada",
                      "start_date": "2026-04-28",
                      "end_date": ""
                    }
                  ],
                  "total_communications": 12,
                  "top_organizations": [
                    { "organization_name": "Example Housing Association", "count": 3 }
                  ]
                }
              ]
            }
            """.utf8
        )
    }
}

private struct CabinetLobbyingNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum CabinetLobbyingMockURLProtocolError: Error {
    case missingHandler
}

private final class CabinetLobbyingMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw CabinetLobbyingMockURLProtocolError.missingHandler
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
