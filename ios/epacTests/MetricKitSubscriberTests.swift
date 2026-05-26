@testable import epac
import Foundation
import MetricKit
import Testing

@Suite(.serialized)
struct MetricKitSubscriberTests {
    @Test func metricPayloadIsForwardedToTelemetry() throws {
        let original = Telemetry.provider
        defer { Telemetry.provider = original }
        let recording = RecordingTelemetryProvider()
        Telemetry.provider = recording

        let begin = Date(timeIntervalSince1970: 1_775_000_000)
        let end = begin.addingTimeInterval(86_400)
        let payload = MockMXMetricPayload(
            jsonData: Data(#"{"metric":true}"#.utf8),
            periodBegin: begin,
            periodEnd: end
        )

        MetricKitSubscriber.shared.didReceive([payload])

        let call = try #require(recording.store.payloads.first)
        #expect(recording.store.payloads.count == 1)
        #expect(call.name == "metrickit.metric")
        #expect(!call.body.isEmpty)
        #expect(call.attributes["period_begin"] == ISO8601DateFormatter().string(from: begin))
        #expect(call.attributes["period_end"] == ISO8601DateFormatter().string(from: end))
    }

    @Test func oversizedMetricPayloadIsTruncatedBeforeForwarding() throws {
        let original = Telemetry.provider
        defer { Telemetry.provider = original }
        let recording = RecordingTelemetryProvider()
        Telemetry.provider = recording

        let payloadSize = 80 * 1_024
        let maxBodySize = 64 * 1_024
        let payload = MockMXMetricPayload(
            jsonData: Data(repeating: UInt8(ascii: "a"), count: payloadSize),
            periodBegin: Date(timeIntervalSince1970: 1_775_000_000),
            periodEnd: Date(timeIntervalSince1970: 1_775_086_400)
        )

        MetricKitSubscriber.shared.didReceive([payload])

        let call = try #require(recording.store.payloads.first)
        #expect(call.name == "metrickit.metric")
        #expect(call.body.utf8.count <= maxBodySize)
        #expect(call.attributes["truncated_bytes"] == "\(payloadSize - maxBodySize)")
    }

    @Test func diagnosticPayloadIsForwardedToTelemetry() throws {
        let original = Telemetry.provider
        defer { Telemetry.provider = original }
        let recording = RecordingTelemetryProvider()
        Telemetry.provider = recording

        let payload = MockMXDiagnosticPayload(
            jsonData: Data(#"{"diagnostic":true}"#.utf8),
            periodBegin: Date(timeIntervalSince1970: 1_775_000_000),
            periodEnd: Date(timeIntervalSince1970: 1_775_086_400)
        )

        MetricKitSubscriber.shared.didReceive([payload])

        let call = try #require(recording.store.payloads.first)
        #expect(recording.store.payloads.count == 1)
        #expect(call.name == "metrickit.diagnostic")
        #expect(!call.body.isEmpty)
    }
}

private final class MockMXMetricPayload: MXMetricPayload {
    private let jsonData: Data
    private let periodBegin: Date
    private let periodEnd: Date

    init(jsonData: Data, periodBegin: Date, periodEnd: Date) {
        self.jsonData = jsonData
        self.periodBegin = periodBegin
        self.periodEnd = periodEnd
        super.init()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var timeStampBegin: Date {
        periodBegin
    }

    override var timeStampEnd: Date {
        periodEnd
    }

    override func jsonRepresentation() -> Data {
        jsonData
    }
}

private final class MockMXDiagnosticPayload: MXDiagnosticPayload {
    private let jsonData: Data
    private let periodBegin: Date
    private let periodEnd: Date

    init(jsonData: Data, periodBegin: Date, periodEnd: Date) {
        self.jsonData = jsonData
        self.periodBegin = periodBegin
        self.periodEnd = periodEnd
        super.init()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var timeStampBegin: Date {
        periodBegin
    }

    override var timeStampEnd: Date {
        periodEnd
    }

    override func jsonRepresentation() -> Data {
        jsonData
    }
}
