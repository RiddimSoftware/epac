@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BackendTelemetryProviderTests {
    @Test func recordingThirtyEventsTriggersFlush() async throws {
        let recorder = TelemetryHTTPRecorder()
        let harness = try makeHarness(recorder: recorder)
        defer { harness.cleanup() }

        for index in 0..<30 {
            harness.provider.recordEvent("event.\(index)", attributes: ["index": "\(index)"])
        }

        #expect(await recorder.waitForRequestCount(1))
        let request = try #require(recorder.snapshot().first)
        let envelope = try request.decodedEnvelope()

        #expect(request.request.httpMethod == "POST")
        #expect(request.request.url?.path == "/api/v1/telemetry")
        #expect(request.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(envelope.deviceID == "test-device-id")
        #expect(envelope.appVersion == "1.2.3")
        #expect(envelope.osVersion == "18.1")
        #expect(envelope.events.count == 30)
        #expect(envelope.events.first?.type == "event")
        #expect(envelope.events.first?.name == "event.0")
    }

    @Test func recordingFewerThanThirtyEventsFlushesAfterInterval() async throws {
        let recorder = TelemetryHTTPRecorder()
        let harness = try makeHarness(recorder: recorder, flushInterval: 0.05)
        defer { harness.cleanup() }

        harness.provider.recordEvent("event.one")
        harness.provider.recordEvent("event.two")

        #expect(await recorder.waitForRequestCount(1))
        let envelope = try #require(recorder.snapshot().first).decodedEnvelope()

        #expect(envelope.events.map(\.name) == ["event.one", "event.two"])
    }

    @Test func queueDropsOldestEventsWhenFlushIsBlocked() async throws {
        let recorder = TelemetryHTTPRecorder()
        let firstRequestGate = DispatchSemaphore(value: 0)
        let harness = try makeHarness { request, body in
            recorder.append(request: request, body: body)
            if recorder.count == 1 {
                _ = firstRequestGate.wait(timeout: .now() + 5)
            }
            return Self.noContentResponse(for: request)
        }
        defer { harness.cleanup() }

        harness.provider.recordEvent("blocking")
        harness.provider.flush()
        #expect(await recorder.waitForRequestCount(1))

        for index in 0..<350 {
            harness.provider.recordEvent("event.\(index)")
        }
        try await Task.sleep(for: .milliseconds(200))
        firstRequestGate.signal()

        #expect(await recorder.waitForRequestCount(2))
        let secondEnvelope = try #require(recorder.snapshot().dropFirst().first).decodedEnvelope()

        #expect(secondEnvelope.events.count == 300)
        #expect(secondEnvelope.events.first?.name == "event.50")
        #expect(secondEnvelope.events.last?.name == "event.349")
    }

    @Test func finishingSpanRecordsDuration() async throws {
        let recorder = TelemetryHTTPRecorder()
        let harness = try makeHarness(recorder: recorder, batchSize: 1)
        defer { harness.cleanup() }

        let span = harness.provider.startSpan(name: "api.fetch", operation: "GET /api/v1/sittings")
        try await Task.sleep(for: .milliseconds(25))
        span.finish()

        #expect(await recorder.waitForRequestCount(1))
        let event = try #require(recorder.snapshot().first?.decodedEnvelope().events.first)

        #expect(event.type == "span")
        #expect(event.name == "api.fetch")
        #expect(event.operation == "GET /api/v1/sittings")
        #expect((event.durationMs ?? 0) >= 20)
    }

    @Test func payloadBypassesSmallEventBatchAndUsesOneRequestPerPayload() async throws {
        let recorder = TelemetryHTTPRecorder()
        let harness = try makeHarness(recorder: recorder)
        defer { harness.cleanup() }

        harness.provider.recordEvent("queued.small.event")
        harness.provider.recordPayload(name: "payload.one", body: #"{"one":true}"#)
        harness.provider.recordPayload(name: "payload.two", body: #"{"two":true}"#)

        #expect(await recorder.waitForRequestCount(2))
        let envelopes = try recorder.snapshot().prefix(2).map { try $0.decodedEnvelope() }

        #expect(envelopes.allSatisfy { $0.events.count == 1 })
        #expect(envelopes.map { $0.events[0].type } == ["payload", "payload"])
        #expect(envelopes.map { $0.events[0].name } == ["payload.one", "payload.two"])
    }

    @Test func postFailureIsSwallowedAndDoesNotExceedNetworkRetryBudget() async throws {
        let recorder = TelemetryHTTPRecorder()
        let delays = TelemetryDelayRecorder()
        let harness = try makeHarness(
            batchSize: 1,
            sleep: { delay in await delays.append(delay) }
        ) { request, body in
            recorder.append(request: request, body: body)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "0"]
                )!,
                Data()
            )
        }
        defer { harness.cleanup() }

        harness.provider.recordEvent("rate.limited")

        #expect(await recorder.waitForRequestCount(4))
        #expect(recorder.count == 4)
        #expect(await delays.values == [0, 0, 0])
    }

    private func makeHarness(
        recorder: TelemetryHTTPRecorder,
        batchSize: Int = 30,
        flushInterval: TimeInterval = 10
    ) throws -> BackendTelemetryProviderHarness {
        try makeHarness(batchSize: batchSize, flushInterval: flushInterval) { request, body in
            recorder.append(request: request, body: body)
            return Self.noContentResponse(for: request)
        }
    }

    private func makeHarness(
        batchSize: Int = 30,
        flushInterval: TimeInterval = 10,
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in },
        handler: @escaping @Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data)
    ) throws -> BackendTelemetryProviderHarness {
        TelemetryMockURLProtocol.requestHandler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "BackendTelemetryProviderTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendTelemetryProviderTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
        let networkService = NetworkService(session: session, cacheStore: cacheStore, sleep: sleep)
        let provider = BackendTelemetryProvider(
            networkService: networkService,
            baseURL: URL(string: "https://telemetry.example.test")!,
            userDefaults: userDefaults,
            appVersion: "1.2.3",
            osVersion: "18.1",
            uuidProvider: { "test-device-id" },
            batchSize: batchSize,
            flushInterval: flushInterval
        )

        return BackendTelemetryProviderHarness(
            provider: provider,
            session: session,
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }

    private static func noContentResponse(for request: URLRequest) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data()
        )
    }
}

private struct BackendTelemetryProviderHarness {
    let provider: BackendTelemetryProvider
    let session: URLSession
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        TelemetryMockURLProtocol.requestHandler = nil
        session.invalidateAndCancel()
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private struct RecordedTelemetryHTTPRequest: Sendable {
    let request: URLRequest
    let body: Data

    func decodedEnvelope() throws -> TelemetryRequestEnvelope {
        try JSONDecoder().decode(TelemetryRequestEnvelope.self, from: body)
    }
}

private final class TelemetryHTTPRecorder: @unchecked Sendable {
    private enum Constants {
        static let pollIntervalMilliseconds = 10
    }

    private let lock = NSLock()
    private var requests: [RecordedTelemetryHTTPRequest] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func append(request: URLRequest, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(RecordedTelemetryHTTPRequest(request: request, body: body))
    }

    func snapshot() -> [RecordedTelemetryHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func waitForRequestCount(_ expectedCount: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while count < expectedCount && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(Constants.pollIntervalMilliseconds))
        }
        return count >= expectedCount
    }
}

private actor TelemetryDelayRecorder {
    private var delays: [Double] = []

    var values: [Double] {
        delays
    }

    func append(_ delay: Double) {
        delays.append(delay)
    }
}

private struct TelemetryRequestEnvelope: Decodable {
    let deviceID: String
    let appVersion: String
    let osVersion: String
    let events: [TelemetryEventEnvelope]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case events
    }
}

private struct TelemetryEventEnvelope: Decodable {
    let type: String
    let name: String
    let operation: String?
    let durationMs: Int?
    let body: String?
    let attributes: [String: String]?

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case operation
        case durationMs = "duration_ms"
        case body
        case attributes
    }
}

private enum TelemetryMockURLProtocolError: Error {
    case missingHandler
}

private final class TelemetryMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw TelemetryMockURLProtocolError.missingHandler
            }

            let (response, data) = try handler(request, Self.bodyData(from: request))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: bufferSize)
            if readCount <= 0 { break }
            data.append(buffer, count: readCount)
        }
        return data
    }
}
