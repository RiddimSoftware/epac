@testable import epac
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct MPBiographyRepositoryTests {
	@Test func backendRepositoryDecodesBiographyProfile() async throws {
		let baseURL = URL(string: "https://example.test")!
		let harness = try makeHarness()
		var capturedURL: URL?

		MPBiographyMockURLProtocol.requestHandler = { request in
			capturedURL = request.url
			return (
				HTTPURLResponse(
					url: try #require(request.url),
					statusCode: 200,
					httpVersion: nil,
					headerFields: ["Content-Type": "application/json"]
				)!,
				Self.memberProfileJSON()
			)
		}

		defer { harness.cleanup() }
		defer { MPBiographyMockURLProtocol.requestHandler = nil }

		let repository = BackendMPBiographyRepository(
			network: harness.service,
			baseURL: baseURL
		)

		let biography = try await repository.loadBiography(memberID: 2269)

		#expect(capturedURL?.path == "/api/v1/members/2269")
		#expect(biography.yearsServed.map(\.displayText) == ["45-1: 2025-04-28 - Present"])
		#expect(biography.previousRoles.first?.displayText == "Shadow Minister for Health (2022-09-01 - 2024-01-30)")
		#expect(biography.education == ["University of Ottawa, MD"])
		#expect(biography.professionalBackground == ["Family physician before entering Parliament."])
		#expect(biography.sponsoredBills.first?.number == "C-234")
		#expect(biography.sourceURL?.absoluteString == "https://www.ourcommons.ca/Members/en/2269")
	}

	@Test func loadUseCaseDelegatesToRepository() async throws {
		let expected = MemberBiography(
			yearsServed: [],
			previousRoles: [],
			education: ["McGill University"],
			professionalBackground: [],
			sponsoredBills: [],
			sourceURL: URL(string: "https://www.ourcommons.ca/Members/en/1"),
			officialProfileURL: URL(string: "https://www.ourcommons.ca/Members/en/1")
		)
		let repository = StubMPBiographyRepository(biography: expected)
		let useCase = LoadMPBiography(repository: repository)

		let loaded = try await useCase.execute(memberID: 1)

		#expect(repository.requestedMemberIDs == [1])
		#expect(loaded == expected)
	}

	@Test func sourceOnlyBiographyDoesNotRenderAsContent() {
		let biography = MemberBiography(
			yearsServed: [],
			previousRoles: [],
			education: [],
			professionalBackground: [],
			sponsoredBills: [],
			sourceURL: URL(string: "https://www.ourcommons.ca/Members/en/1"),
			officialProfileURL: URL(string: "https://www.ourcommons.ca/Members/en/1")
		)

		#expect(!biography.hasDisplayContent)
	}

	private func makeHarness() throws -> MPBiographyNetworkHarness {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [MPBiographyMockURLProtocol.self]
		let session = URLSession(configuration: configuration)

		let suiteName = "MPBiographyRepositoryTests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: suiteName))
		userDefaults.removePersistentDomain(forName: suiteName)

		let cacheDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("MPBiographyRepositoryTests-\(UUID().uuidString)", isDirectory: true)
		let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

		return MPBiographyNetworkHarness(
			service: NetworkService(session: session, cacheStore: cacheStore),
			userDefaultsSuiteName: suiteName,
			cacheDirectory: cacheDirectory
		)
	}

	private static func memberProfileJSON() -> Data {
		Data(
			"""
			{
			  "member": {
			    "id": "2269",
			    "name": "Jane Example",
			    "profile_url": "https://www.ourcommons.ca/Members/en/2269",
			    "biography": {
			      "years_served": [
			        { "label": "45-1", "from_date": "2025-04-28" }
			      ],
			      "previous_roles": [
			        { "title": "Shadow Minister for Health", "start_date": "2022-09-01", "end_date": "2024-01-30" }
			      ],
			      "education": ["University of Ottawa, MD"],
			      "professional_background": "Family physician before entering Parliament.",
			      "source_url": "https://www.ourcommons.ca/Members/en/2269"
			    },
			    "pmb_sponsorships": [
			      {
			        "id": "sponsored-c-234",
			        "bill_number": "C-234",
			        "title": "Living Donor Recognition Medal Act",
			        "relationship": "sponsored",
			        "legis_info_url": "https://www.parl.ca/legisinfo/en/bill/45-1/c-234"
			      }
			    ]
			  }
			}
			""".utf8
		)
	}
}

@MainActor
private final class StubMPBiographyRepository: MPBiographyRepository {
	private let biography: MemberBiography
	var requestedMemberIDs: [Int] = []

	init(biography: MemberBiography) {
		self.biography = biography
	}

	func loadBiography(memberID: Int) async throws -> MemberBiography {
		requestedMemberIDs.append(memberID)
		return biography
	}
}

private struct MPBiographyNetworkHarness {
	let service: NetworkService
	let userDefaultsSuiteName: String
	let cacheDirectory: URL

	func cleanup() {
		UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
		try? FileManager.default.removeItem(at: cacheDirectory)
	}
}

private enum MPBiographyMockURLProtocolError: Error {
	case missingHandler
}

private final class MPBiographyMockURLProtocol: URLProtocol {
	nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

	override static func canInit(with request: URLRequest) -> Bool {
		true
	}

	override static func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		do {
			guard let handler = Self.requestHandler else {
				throw MPBiographyMockURLProtocolError.missingHandler
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
