@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct MPLobbyingExposureRepositoryTests {
	@Test func mpLobbyingExposureDecodesBackendResponse() async throws {
		let baseURL = URL(string: "https://example.test")!
		let harness = try makeHarness()
		var capturedURL: URL?

		MPLobbyingMockURLProtocol.requestHandler = { request in
			capturedURL = request.url
			return (
				HTTPURLResponse(
					url: try #require(request.url),
					statusCode: 200,
					httpVersion: nil,
					headerFields: ["Content-Type": "application/json"]
				)!,
				Self.mpLobbyingExposureJSON()
			)
		}

		defer { harness.cleanup() }
		defer { MPLobbyingMockURLProtocol.requestHandler = nil }

		let repository = BackendMPLobbyingExposureRepository(
			network: harness.service,
			baseURL: baseURL
		)

		let exposure = try await repository.loadMPLobbyingExposure(
			memberID: 278707,
			parliament: 45,
			window: .threeMonths,
			page: 1
		)

		let requestURL = try #require(capturedURL)
		let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
		#expect(components.path == "/api/v1/members/278707/lobbying-exposure")
		#expect(components.queryItems?.first(where: { $0.name == "parliament" })?.value == "45")
		#expect(components.queryItems?.first(where: { $0.name == "window" })?.value == "3m")
		#expect(components.queryItems?.first(where: { $0.name == "page" })?.value == "1")
		#expect(exposure.memberID == "278707")
		#expect(exposure.parliament == 45)
		#expect(exposure.window == .threeMonths)
		#expect(exposure.perPage == MPLobbyingExposureDefaults.pageSize)
		#expect(exposure.summary.totalCommunicationCount == 12)
		#expect(exposure.summary.uniqueOrganizationsCount == 5)
		#expect(exposure.summary.topOrganizations[0].name == "Example Housing Association")
		#expect(exposure.summary.topOrganizations[0].sector == "Housing")
		#expect(exposure.summary.trendVsPreviousParliament.delta == 8)
		#expect(exposure.summary.partyAverageCommunications == 4.25)
		#expect(exposure.summary.nationalAverageCommunications == 3.75)
		#expect(exposure.subjectBreakdown[0].subjectMatter == "Housing")
		#expect(exposure.timeline[0].organizationName == "Example Housing Association")
		#expect(exposure.timeline[0].organizationSector == "Housing")
		#expect(exposure.timeline[0].subjectMatter == "Housing")
		#expect(exposure.timeline[0].communicationType == "meeting")
		#expect(exposure.timeline[0].billCrossReference?.billNumber == "C-1")
		#expect(exposure.timeline[0].billCrossReference?.mappingConfidence == 0.93)
		#expect(exposure.sourceURL == CabinetLobbyingSource.url)
	}

	private func makeHarness() throws -> MPLobbyingNetworkHarness {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [MPLobbyingMockURLProtocol.self]
		let session = URLSession(configuration: configuration)

		let suiteName = "MPLobbyingExposureRepositoryTests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: suiteName))
		userDefaults.removePersistentDomain(forName: suiteName)

		let cacheDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("MPLobbyingExposureRepositoryTests-\(UUID().uuidString)", isDirectory: true)
		let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

		return MPLobbyingNetworkHarness(
			service: NetworkService(session: session, cacheStore: cacheStore),
			userDefaultsSuiteName: suiteName,
			cacheDirectory: cacheDirectory
		)
	}

	private static func mpLobbyingExposureJSON() -> Data {
		Data(
			"""
			{
			  "member_id": "278707",
			  "parliament": 45,
			  "window": "3m",
			  "page": 1,
			  "per_page": 50,
			  "total": 2,
			  "pages": 1,
			  "summary": {
			    "member_id": "278707",
			    "parliament": 45,
			    "quarter_start": "2026-04-01T00:00:00Z",
			    "window": "3m",
			    "total_communication_count": 12,
			    "unique_organizations_count": 5,
			    "most_frequent_subject_matter": "Housing",
			    "top_organizations": [
			      { "name": "Example Housing Association", "sector": "Housing", "communication_count": 6 },
			      { "name": "National Builders Council", "sector": "Infrastructure", "communication_count": 4 }
			    ],
			    "trend_vs_previous_parliament": {
			      "current_parliament": 12,
			      "previous_parliament": 4,
			      "delta": 8
			    },
			    "party_average_communications": 4.25,
			    "national_average_communications": 3.75,
			    "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
			    "updated_at": "2026-06-30T12:00:00Z"
			  },
			  "subject_breakdown": [
			    { "subject_matter": "Housing", "communication_count": 8 },
			    { "subject_matter": "Infrastructure", "communication_count": 4 }
			  ],
			  "timeline": [
			    {
			      "communication_id": "558142",
			      "date": "2026-05-20",
			      "organization_name": "Example Housing Association",
			      "organization_sector": "Housing",
			      "subject_matter": "Housing",
			      "communication_type": "meeting",
			      "bill_cross_reference": {
			        "bill_number": "C-1",
			        "bill_title": "Example Bill",
			        "url": "https://www.parl.ca/legisinfo/en/bill/45-1/c-1",
			        "mapping_confidence": 0.93
			      },
			      "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
			      "source_url": "https://lobbycanada.gc.ca/en/open-data/"
			    }
			  ],
			  "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
			  "source_url": "https://lobbycanada.gc.ca/en/open-data/"
			}
			""".utf8
		)
	}
}

private struct MPLobbyingNetworkHarness {
	let service: NetworkService
	let userDefaultsSuiteName: String
	let cacheDirectory: URL

	func cleanup() {
		UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
		try? FileManager.default.removeItem(at: cacheDirectory)
	}
}

private enum MPLobbyingMockURLProtocolError: Error {
	case missingHandler
}

private final class MPLobbyingMockURLProtocol: URLProtocol {
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
				throw MPLobbyingMockURLProtocolError.missingHandler
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
