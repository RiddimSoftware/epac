@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct GazetteServiceTests {

    @Test func fetchAllCombinesAndSortsParts() async throws {
        let p1Data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Part I Notice</title>
                    <link>https://gazette.gc.ca/p1</link>
                    <pubDate>Sat, 09 May 2026 14:00:00 -0500</pubDate>
                    <description>P1 Description</description>
                    <category>Notice</category>
                </item>
            </channel>
        </rss>
        """.utf8)

        let p2Data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Part II Regulation</title>
                    <link>https://gazette.gc.ca/p2</link>
                    <pubDate>Wed, 06 May 2026 09:00:00 -0500</pubDate>
                    <description>P2 Description</description>
                    <category>Regulation</category>
                </item>
            </channel>
        </rss>
        """.utf8)

        // We use MockURLProtocol to intercept calls from NetworkService.shared (which uses URLSession.shared)
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let data = url.absoluteString.contains("p1-eng.xml") ? p1Data : p2Data
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let entries = try await GazetteService.fetchAll()

        #expect(entries.count == 2)
        #expect(entries[0].title == "Part I Notice")
        #expect(entries[0].part == .partI)
        #expect(entries[1].title == "Part II Regulation")
        #expect(entries[1].part == .partII)

        // Verify sorting (newest first)
        #expect(entries[0].publicationDate > entries[1].publicationDate)
    }

    @Test func fetchPartIFailsReturnsError() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { MockURLProtocol.requestHandler = nil }

        await #expect(throws: URLError.self) {
            try await GazetteService.fetch(part: .partI)
        }
    }
}

// MockURLProtocol duplicate for these tests since we can't easily share private classes from other test files
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
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
