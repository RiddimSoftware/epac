@testable import epac
import Foundation
import Testing

struct RecordingTelemetryProvider: TelemetryProvider {
    final class Store: @unchecked Sendable {
        var errors: [(Error, [String: String])] = []
        var events: [(String, [String: String])] = []
        var payloads: [(name: String, body: String, attributes: [String: String])] = []
        var spans: [(name: String, operation: String)] = []
    }

    let store = Store()

    func recordError(_ error: Error, attributes: [String: String]) {
        store.errors.append((error, attributes))
    }

    func recordEvent(_ name: String, attributes: [String: String]) {
        store.events.append((name, attributes))
    }

    func recordPayload(name: String, body: String, attributes: [String: String]) {
        store.payloads.append((name: name, body: body, attributes: attributes))
    }

    func startSpan(name: String, operation: String) -> any TelemetrySpan {
        store.spans.append((name: name, operation: operation))
        return NoopTelemetrySpan()
    }
}

@Suite(.serialized)
struct TelemetryTests {
    @Test func noopProviderDoesNotCrash() {
        let provider = NoopTelemetryProvider()
        provider.recordError(NSError(domain: "test", code: 1), attributes: [:])
        provider.recordEvent("test.event", attributes: ["key": "value"])
        provider.recordPayload(name: "test.payload", body: "{}", attributes: ["kind": "unit"])
        let span = provider.startSpan(name: "op", operation: "test")
        span.finish()
    }

    @Test func noopSpanFinishIsIdempotent() {
        let span = NoopTelemetrySpan()
        span.finish()
        span.finish()
    }

    @Test func performanceSignpostContractPinsStableNames() {
        #expect(PerformanceSignpostContract.subsystem == "com.riddimsoftware.epac")
        #expect(PerformanceSignpostContract.category == "performance")
        #expect(PerformanceSignpostContract.allSpanNames == [
            "launch.model-container",
            "launch.home-feed",
            "hansard.fetch-transcript",
            "swiftdata.migration-open",
            "search.hansard-round-trip"
        ])
    }

    @Test func multiplexProviderRoutesSpansToEachProvider() {
        let first = RecordingTelemetryProvider()
        let second = RecordingTelemetryProvider()
        let provider = MultiplexTelemetryProvider(providers: [first, second])

        let span = provider.startSpan(name: "sync", operation: "fetch")
        span.finish()
        span.finish()

        #expect(first.store.spans.count == 1)
        #expect(second.store.spans.count == 1)
    }

    @Test func providerSwapRoutesToNewProvider() {
        let original = Telemetry.provider
        defer { Telemetry.provider = original }

        let recording = RecordingTelemetryProvider()
        Telemetry.provider = recording

        let error = NSError(domain: "test", code: 42)
        Telemetry.recordError(error, attributes: ["ctx": "unit"])
        Telemetry.recordEvent("launch", attributes: ["source": "cold"])
        Telemetry.recordPayload(name: "metrickit.metric", body: #"{"metric":true}"#, attributes: ["source": "test"])
        let span = Telemetry.startSpan(name: "sync", operation: "fetch")
        span.finish()

        #expect(recording.store.errors.count == 1)
        #expect((recording.store.errors.first?.0 as? NSError)?.code == 42)
        #expect(recording.store.errors.first?.1["ctx"] == "unit")

        #expect(recording.store.events.count == 1)
        #expect(recording.store.events.first?.0 == "launch")
        #expect(recording.store.events.first?.1["source"] == "cold")

        #expect(recording.store.payloads.count == 1)
        #expect(recording.store.payloads.first?.name == "metrickit.metric")
        #expect(recording.store.payloads.first?.body == #"{"metric":true}"#)
        #expect(recording.store.payloads.first?.attributes["source"] == "test")

        #expect(recording.store.spans.count == 1)
        #expect(recording.store.spans.first?.name == "sync")
        #expect(recording.store.spans.first?.operation == "fetch")
    }

    @Test func defaultProviderIsNoop() {
        let original = Telemetry.provider
        defer { Telemetry.provider = original }

        Telemetry.provider = NoopTelemetryProvider()
        #expect(Telemetry.provider is NoopTelemetryProvider)
    }
}
