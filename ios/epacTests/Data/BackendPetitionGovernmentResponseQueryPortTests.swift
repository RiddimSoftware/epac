//
//  BackendPetitionGovernmentResponseQueryPortTests.swift
//  epacTests
//

@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BackendPetitionGovernmentResponseQueryPortTests {
    
    @Test func fetchGovernmentResponseSuccess() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedURL: URL?
        
        PetitionMockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.mockResponseJSON()
            )
        }
        
        defer { harness.cleanup() }
        defer { PetitionMockURLProtocol.requestHandler = nil }
        
        let port = BackendPetitionGovernmentResponseQueryPort(
            network: harness.service,
            baseURL: baseURL
        )
        
        let response = try await port.fetchGovernmentResponse(for: "e-4500")
        
        let requestURL = try #require(capturedURL)
        #expect(requestURL.absoluteString == "https://example.test/api/v1/petitions/e-4500/response")
        
        let val = try #require(response)
        #expect(val.text == "This is the government's response.")
        #expect(val.respondingMinister == "Minister of Health")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let expectedDate = formatter.date(from: "2026-05-15")!
        #expect(val.tabledOn == expectedDate)
    }
    
    @Test func fetchGovernmentResponseReturnsNilOn404() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        
        PetitionMockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        
        defer { harness.cleanup() }
        defer { PetitionMockURLProtocol.requestHandler = nil }
        
        let port = BackendPetitionGovernmentResponseQueryPort(
            network: harness.service,
            baseURL: baseURL
        )
        
        let response = try await port.fetchGovernmentResponse(for: "e-4500")
        #expect(response == nil)
    }
    
    @Test func fetchGovernmentResponseThrowsOn500() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        
        PetitionMockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        
        defer { harness.cleanup() }
        defer { PetitionMockURLProtocol.requestHandler = nil }
        
        let port = BackendPetitionGovernmentResponseQueryPort(
            network: harness.service,
            baseURL: baseURL
        )
        
        await #expect(throws: URLError.self) {
            _ = try await port.fetchGovernmentResponse(for: "e-4500")
        }
    }
    
    private func makeHarness() throws -> PetitionNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PetitionMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        
        let suiteName = "BackendPetitionGovernmentResponseQueryPortTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendPetitionGovernmentResponseQueryPortTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
        
        return PetitionNetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }
    
    private static func mockResponseJSON() -> Data {
        """
        {
          "text": "This is the government's response.",
          "tabled_on": "2026-05-15",
          "responding_minister": "Minister of Health"
        }
        """.data(using: .utf8)!
    }
}

private struct PetitionNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL
    
    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum PetitionMockURLProtocolError: Error {
    case missingHandler
}

private final class PetitionMockURLProtocol: URLProtocol {
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
                throw PetitionMockURLProtocolError.missingHandler
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
