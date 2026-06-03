@testable import epac
import Foundation
import Testing

private enum LobbyistOrganizationTestConstants {
	static let currentParliamentCommunications = 8
	static let priorParliamentCommunications = 5
	static let dpohContactCount = 4
	static let recentCommunicationDate = ISO8601DateFormatter().date(from: "2026-05-20T00:00:00Z")!
	static let registrationSourceURL = URL(
		string: "https://www.lobbycanada.gc.ca/app/secure/ocl/lrs/do/rgstrnCmmnctnRprts?lang=eng&regId=990018"
	)!
	static let subjectCommunicationCount = 6
}

@Suite(.serialized)
struct LobbyistOrganizationRepositoryTests {
	@Test func profileDecodesBackendResponse() async throws {
		let baseURL = URL(string: "https://example.test")!
		let harness = try makeHarness()
		var capturedURL: URL?

		LobbyistOrganizationMockURLProtocol.requestHandler = { request in
			capturedURL = request.url
			return (
				HTTPURLResponse(
					url: try #require(request.url),
					statusCode: 200,
					httpVersion: nil,
					headerFields: ["Content-Type": "application/json"]
				)!,
				Self.profileJSON()
			)
		}

		defer { harness.cleanup() }
		defer { LobbyistOrganizationMockURLProtocol.requestHandler = nil }

		let repository = BackendLobbyistOrganizationRepository(
			network: harness.service,
			baseURL: baseURL
		)

		let profile = try await repository.loadLobbyistOrganizationProfile(id: "ocl:42")

		#expect(capturedURL?.path == "/api/v1/lobbying/organizations/ocl:42")
		#expect(profile.id == "ocl:42")
		#expect(profile.name == "Canadian Housing Alliance")
		#expect(profile.registrationStatus == .active)
		#expect(profile.registrations[0].kind == .consultant)
		#expect(profile.recentCommunications[0].dpohMemberID == "278707")
		#expect(profile.subjectMatters[0].topicSlug == "housing")
		#expect(profile.sourceURL == LobbyistOrganizationTestConstants.registrationSourceURL)
	}

	@Test func useCaseResolvesOrganizationNameThroughDirectory() async throws {
		let repository = LobbyistOrganizationRepositorySpy()
		let useCase = LoadLobbyistOrganizationProfile(repository: repository)

		let profile = try await useCase.execute(organizationName: "Canadian Housing Alliance")

		#expect(repository.browsedSearch == "Canadian Housing Alliance")
		#expect(repository.loadedID == "ocl:42")
		#expect(profile.id == "ocl:42")
	}

	private func makeHarness() throws -> LobbyistOrganizationNetworkHarness {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [LobbyistOrganizationMockURLProtocol.self]
		let session = URLSession(configuration: configuration)

		let suiteName = "LobbyistOrganizationRepositoryTests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: suiteName))
		userDefaults.removePersistentDomain(forName: suiteName)

		let cacheDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LobbyistOrganizationRepositoryTests-\(UUID().uuidString)", isDirectory: true)
		let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

		return LobbyistOrganizationNetworkHarness(
			service: NetworkService(session: session, cacheStore: cacheStore),
			userDefaultsSuiteName: suiteName,
			cacheDirectory: cacheDirectory
		)
	}

	private static func profileJSON() -> Data {
		Data(
			"""
			{
			  "id": "ocl:42",
			  "ocl_organization_id": "42",
			  "name": "Canadian Housing Alliance",
			  "type": "association",
			  "sector": "Housing",
			  "registered_lobbyists": [
			    { "name": "Jane Lobbyist", "kind": "consultant" }
			  ],
			  "active_subject_matters": ["Housing", "Infrastructure"],
			  "communication_volume": {
			    "current_parliament": 8,
			    "prior_parliament": 5
			  },
			  "top_dpohs_contacted": [
			    {
			      "member_id": "278707",
			      "name": "Example Minister",
			      "institution": "House of Commons",
			      "count": 4
			    }
			  ],
			  "registration_status": "active",
			  "registrations": [
			    {
			      "id": "990018",
			      "status": "active",
			      "kind": "consultant",
			      "subject_matters": ["Housing", "Infrastructure"],
			      "targeted_institutions": ["House of Commons"],
			      "source_url": "\(LobbyistOrganizationTestConstants.registrationSourceURL.absoluteString)"
			    }
			  ],
			  "recent_communications": [
			    {
			      "id": "558142",
			      "date": "2026-05-20",
			      "dpoh_member_id": "278707",
			      "dpoh_name": "Example Minister",
			      "institution": "House of Commons",
			      "subject_matters": ["Housing"],
			      "source_url": "https://lobbycanada.gc.ca/en/open-data/"
			    }
			  ],
			  "subject_matters": [
			    { "subject_matter": "Housing", "communication_count": 6, "topic_slug": "housing" }
			  ],
			  "citation": "Source: Office of the Commissioner of Lobbying (OCL)",
			  "source_url": "\(LobbyistOrganizationTestConstants.registrationSourceURL.absoluteString)"
			}
			""".utf8
		)
	}
}

private final class LobbyistOrganizationRepositorySpy: LobbyistOrganizationRepository {
	var browsedSearch: String?
	var loadedID: String?

	func loadLobbyistOrganizationProfile(id: String) async throws -> LobbyistOrganization {
		loadedID = id
		return .activeFixture
	}

	func browseLobbyistOrganizations(
		search: String?,
		sector: String?,
		page: Int,
		perPage: Int
	) async throws -> LobbyistOrganizationDirectory {
		browsedSearch = search
		return LobbyistOrganizationDirectory(
			page: page,
			perPage: perPage,
			citation: CabinetLobbyingSource.citation,
			sourceURL: CabinetLobbyingSource.url,
			rows: [
				LobbyistOrganizationDirectoryRow(
					id: "ocl:42",
					name: "Canadian Housing Alliance",
					type: .association,
					sector: sector,
					communicationVolumeCurrentParliament: LobbyistOrganizationTestConstants.currentParliamentCommunications
				)
			]
		)
	}
}

private extension LobbyistOrganization {
	static var activeFixture: LobbyistOrganization {
		LobbyistOrganization(
			id: "ocl:42",
			oclOrganizationID: "42",
			name: "Canadian Housing Alliance",
			type: .association,
			sector: "Housing",
			registeredLobbyists: [
				RegisteredLobbyist(name: "Jane Lobbyist", kind: .consultant)
			],
			activeSubjectMatters: ["Housing", "Infrastructure"],
			communicationVolume: LobbyistOrganizationCommunicationVolume(
				currentParliament: LobbyistOrganizationTestConstants.currentParliamentCommunications,
				priorParliament: LobbyistOrganizationTestConstants.priorParliamentCommunications
			),
			topDPOHsContacted: [
				LobbyistOrganizationDPOHContact(
					memberID: "278707",
					name: "Example Minister",
					institution: "House of Commons",
					count: LobbyistOrganizationTestConstants.dpohContactCount
				)
			],
			registrationStatus: .active,
			registrations: [
				LobbyistRegistration(
					id: "990018",
					status: .active,
					kind: .consultant,
					subjectMatters: ["Housing", "Infrastructure"],
					targetedInstitutions: ["House of Commons"],
					sourceURL: LobbyistOrganizationTestConstants.registrationSourceURL
				)
			],
			recentCommunications: [
				LobbyistOrganizationCommunication(
					id: "558142",
					date: LobbyistOrganizationTestConstants.recentCommunicationDate,
					dpohMemberID: "278707",
					dpohName: "Example Minister",
					institution: "House of Commons",
					subjectMatters: ["Housing"],
					sourceURL: CabinetLobbyingSource.url
				)
			],
			subjectMatters: [
				LobbyistOrganizationSubjectMatter(
					subjectMatter: "Housing",
					communicationCount: LobbyistOrganizationTestConstants.subjectCommunicationCount,
					topicSlug: "housing"
				)
			],
			citation: CabinetLobbyingSource.citation,
			sourceURL: LobbyistOrganizationTestConstants.registrationSourceURL
		)
	}
}

private struct LobbyistOrganizationNetworkHarness {
	let service: NetworkService
	let userDefaultsSuiteName: String
	let cacheDirectory: URL

	func cleanup() {
		UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
		try? FileManager.default.removeItem(at: cacheDirectory)
	}
}

private enum LobbyistOrganizationMockURLProtocolError: Error {
	case missingHandler
}

private final class LobbyistOrganizationMockURLProtocol: URLProtocol {
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
				throw LobbyistOrganizationMockURLProtocolError.missingHandler
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
