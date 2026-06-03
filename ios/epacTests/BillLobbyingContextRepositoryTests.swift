@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BillLobbyingContextRepositoryTests {
	@Test func billLobbyingContextDecodesBackendResponse() async throws {
		let baseURL = URL(string: "https://example.test")!
		let harness = try makeHarness()
		var capturedURL: URL?

		BillLobbyingContextMockURLProtocol.requestHandler = { request in
			capturedURL = request.url
			return (
				HTTPURLResponse(
					url: try #require(request.url),
					statusCode: 200,
					httpVersion: nil,
					headerFields: ["Content-Type": "application/json"]
				)!,
				Self.billLobbyingContextJSON()
			)
		}

		defer { harness.cleanup() }
		defer { BillLobbyingContextMockURLProtocol.requestHandler = nil }

		let repository = BackendBillLobbyingContextRepository(
			network: harness.service,
			baseURL: baseURL
		)

		let context = try await repository.loadBillLobbyingContext(billID: "C-2", windowMonths: 12)

		let requestURL = try #require(capturedURL)
		let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
		#expect(components.path == "/api/v1/bills/C-2/lobbying-context")
		#expect(components.queryItems?.first(where: { $0.name == "window_months" })?.value == "12")
		#expect(context.billID == "C-2")
		#expect(context.windowMonths == 12)
		#expect(context.windowStartDate == expectedUTCDate(year: 2025, month: 5, day: 15))
		#expect(context.windowEndDate == expectedUTCDate(year: 2026, month: 5, day: 15))
		#expect(context.subjectTags == ["Housing"])
		#expect(context.totalCommunications == 8)
		#expect(context.organizations.count == 4)
		#expect(context.topOrganizations.count == 3)
		#expect(context.topOrganizations[0].name == "Example Housing Association")
		#expect(context.topOrganizations[0].communicationCount == 4)
		#expect(context.sourceURL == CabinetLobbyingSource.url)
	}

	private func makeHarness() throws -> BillLobbyingContextNetworkHarness {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [BillLobbyingContextMockURLProtocol.self]
		let session = URLSession(configuration: configuration)

		let suiteName = "BillLobbyingContextRepositoryTests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: suiteName))
		userDefaults.removePersistentDomain(forName: suiteName)

		let cacheDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("BillLobbyingContextRepositoryTests-\(UUID().uuidString)", isDirectory: true)
		let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

		return BillLobbyingContextNetworkHarness(
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

	private static func billLobbyingContextJSON() -> Data {
		Data(
			"""
			{
			  "legisinfo_id": "C-2",
			  "window_months": 12,
			  "window_start_date": "2025-05-15",
			  "window_end_date": "2026-05-15",
			  "subject_tags": ["Housing"],
			  "total_communications": 8,
			  "count_by_organization": [
			    { "organization_name": "Example Housing Association", "count": 4 },
			    { "organization_name": "National Builders Council", "count": 2 },
			    { "organization_name": "Tenant Rights Network", "count": 1 },
			    { "organization_name": "Urban Infrastructure Forum", "count": 1 }
			  ],
			  "count_by_subject_matter": [
			    { "ocl_code": "SMT-44", "subject_matter": "Housing", "count": 8 }
			  ],
			  "top_organizations": [
			    { "organization_name": "Example Housing Association", "count": 4 },
			    { "organization_name": "National Builders Council", "count": 2 },
			    { "organization_name": "Tenant Rights Network", "count": 1 }
			  ],
			  "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
			  "source_url": "https://lobbycanada.gc.ca/en/open-data/"
			}
			""".utf8
		)
	}
}

private struct BillLobbyingContextNetworkHarness {
	let service: NetworkService
	let userDefaultsSuiteName: String
	let cacheDirectory: URL

	func cleanup() {
		UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
		try? FileManager.default.removeItem(at: cacheDirectory)
	}
}

private enum BillLobbyingContextMockURLProtocolError: Error {
	case missingHandler
}

private final class BillLobbyingContextMockURLProtocol: URLProtocol {
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
				throw BillLobbyingContextMockURLProtocolError.missingHandler
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
