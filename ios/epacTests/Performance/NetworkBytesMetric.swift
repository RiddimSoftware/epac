import Foundation
import XCTest

final class NetworkBytesMetric: NSObject, XCTMetric, URLSessionTaskDelegate, @unchecked Sendable {
    static let identifier = "com.riddimsoftware.epac.performance.network-bytes"

    private let recorder: NetworkBytesMetricsRecorder

    var reportedByteCounts: [Int64] {
        recorder.reportedByteCounts
    }

    func waitForCollectedTaskMetrics(timeout: TimeInterval = 1) -> Bool {
        recorder.waitForTaskMetrics(atLeast: 1, timeout: timeout)
    }

    override convenience init() {
        self.init(recorder: NetworkBytesMetricsRecorder())
    }

    private init(recorder: NetworkBytesMetricsRecorder) {
        self.recorder = recorder
        super.init()
    }

    func copy(with zone: NSZone? = nil) -> Any {
        NetworkBytesMetric(recorder: recorder)
    }

    func willBeginMeasuring() {
        recorder.beginIteration()
    }

    func didStopMeasuring() {}

    func reportMeasurements(
        from startTime: XCTPerformanceMeasurementTimestamp,
        to endTime: XCTPerformanceMeasurementTimestamp
    ) throws -> [XCTPerformanceMeasurement] {
        let byteCount = recorder.byteCount()
        recorder.recordReportedByteCount(byteCount)

        return [
            XCTPerformanceMeasurement(
                identifier: Self.identifier,
                displayName: "Debate Load Network Bytes",
                doubleValue: Double(byteCount),
                unitSymbol: "bytes",
                polarity: .prefersSmaller
            )
        ]
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        recorder.record(metrics)
    }
}

private final class NetworkBytesMetricsRecorder: @unchecked Sendable {
    private let condition = NSCondition()
    private var metrics: [URLSessionTaskMetrics] = []
    private var byteCounts: [Int64] = []

    var reportedByteCounts: [Int64] {
        condition.lock()
        defer { condition.unlock() }
        return byteCounts
    }

    func beginIteration() {
        condition.lock()
        metrics.removeAll(keepingCapacity: true)
        condition.unlock()
    }

    func record(_ taskMetrics: URLSessionTaskMetrics) {
        condition.lock()
        metrics.append(taskMetrics)
        condition.broadcast()
        condition.unlock()
    }

    func waitForTaskMetrics(atLeast count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }

        while metrics.count < count {
            guard condition.wait(until: deadline) else {
                return metrics.count >= count
            }
        }
        return true
    }

    func byteCount() -> Int64 {
        condition.lock()
        let currentMetrics = metrics
        condition.unlock()

        return currentMetrics
            .flatMap(\.transactionMetrics)
            .reduce(0) { partialResult, transactionMetrics in
                partialResult + Self.transferredByteCount(for: transactionMetrics)
            }
    }

    func recordReportedByteCount(_ byteCount: Int64) {
        condition.lock()
        byteCounts.append(byteCount)
        condition.unlock()
    }

    private static func transferredByteCount(for metrics: URLSessionTaskTransactionMetrics) -> Int64 {
        [
            metrics.countOfRequestHeaderBytesSent,
            metrics.countOfRequestBodyBytesSent,
            metrics.countOfResponseHeaderBytesReceived,
            metrics.countOfResponseBodyBytesReceived
        ].reduce(0) { partialResult, byteCount in
            partialResult + max(0, byteCount)
        }
    }
}
