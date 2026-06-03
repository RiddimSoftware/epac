import Foundation
import OSLog

protocol TelemetrySpan: Sendable {
    func finish()
}

protocol TelemetryProvider: Sendable {
    func recordError(_ error: Error, attributes: [String: String])
    func recordEvent(_ name: String, attributes: [String: String])
    func recordPayload(name: String, body: String, attributes: [String: String])
    func startSpan(name: String, operation: String) -> any TelemetrySpan
}

extension TelemetryProvider {
    func recordError(_ error: Error) {
        recordError(error, attributes: [:])
    }

    func recordEvent(_ name: String) {
        recordEvent(name, attributes: [:])
    }

    func recordPayload(name: String, body: String) {
        recordPayload(name: name, body: body, attributes: [:])
    }
}

protocol FlushableTelemetryProvider {
    func flush()
}

struct NoopTelemetrySpan: TelemetrySpan {
    func finish() {}
}

struct NoopTelemetryProvider: TelemetryProvider {
    func recordError(_ error: Error, attributes: [String: String] = [:]) {}
    func recordEvent(_ name: String, attributes: [String: String] = [:]) {}
    func recordPayload(name: String, body: String, attributes: [String: String] = [:]) {}
    func startSpan(name: String, operation: String) -> any TelemetrySpan { NoopTelemetrySpan() }
}

enum PerformanceSignpostContract {
    static let subsystem = "com.riddimsoftware.epac"
    static let category = "performance"

    enum SpanName {
        static let launchModelContainer = "launch.model-container"
        static let launchHomeFeed = "launch.home-feed"
        static let hansardFetchTranscript = "hansard.fetch-transcript"
        static let swiftDataMigrationOpen = "swiftdata.migration-open"
        static let searchHansardRoundTrip = "search.hansard-round-trip"
    }

    static let allSpanNames: Set<String> = [
        SpanName.launchModelContainer,
        SpanName.launchHomeFeed,
        SpanName.hansardFetchTranscript,
        SpanName.swiftDataMigrationOpen,
        SpanName.searchHansardRoundTrip
    ]
}

struct MultiplexTelemetryProvider: TelemetryProvider {
    private let providers: [any TelemetryProvider]

    init(providers: [any TelemetryProvider]) {
        self.providers = providers
    }

    func recordError(_ error: Error, attributes: [String: String] = [:]) {
        providers.forEach { $0.recordError(error, attributes: attributes) }
    }

    func recordEvent(_ name: String, attributes: [String: String] = [:]) {
        providers.forEach { $0.recordEvent(name, attributes: attributes) }
    }

    func recordPayload(name: String, body: String, attributes: [String: String] = [:]) {
        providers.forEach { $0.recordPayload(name: name, body: body, attributes: attributes) }
    }

    func startSpan(name: String, operation: String) -> any TelemetrySpan {
        MultiplexTelemetrySpan(
            spans: providers.map { $0.startSpan(name: name, operation: operation) }
        )
    }
}

struct OSSignpostTelemetryProvider: TelemetryProvider {
    private typealias SpanFactory = @Sendable (OSSignposter) -> any TelemetrySpan

    private static let spanFactories: [String: SpanFactory] = [
        PerformanceSignpostContract.SpanName.launchModelContainer: { signposter in
            let state = signposter.beginInterval("launch.model-container")
            return OSSignpostTelemetrySpan {
                signposter.endInterval("launch.model-container", state)
            }
        },
        PerformanceSignpostContract.SpanName.launchHomeFeed: { signposter in
            let state = signposter.beginInterval("launch.home-feed")
            return OSSignpostTelemetrySpan {
                signposter.endInterval("launch.home-feed", state)
            }
        },
        PerformanceSignpostContract.SpanName.hansardFetchTranscript: { signposter in
            let state = signposter.beginInterval("hansard.fetch-transcript")
            return OSSignpostTelemetrySpan {
                signposter.endInterval("hansard.fetch-transcript", state)
            }
        },
        PerformanceSignpostContract.SpanName.swiftDataMigrationOpen: { signposter in
            let state = signposter.beginInterval("swiftdata.migration-open")
            return OSSignpostTelemetrySpan {
                signposter.endInterval("swiftdata.migration-open", state)
            }
        },
        PerformanceSignpostContract.SpanName.searchHansardRoundTrip: { signposter in
            let state = signposter.beginInterval("search.hansard-round-trip")
            return OSSignpostTelemetrySpan {
                signposter.endInterval("search.hansard-round-trip", state)
            }
        }
    ]

    private let signposter: OSSignposter

    init(
        subsystem: String = PerformanceSignpostContract.subsystem,
        category: String = PerformanceSignpostContract.category
    ) {
        self.signposter = OSSignposter(subsystem: subsystem, category: category)
    }

    func recordError(_ error: Error, attributes: [String: String] = [:]) {}
    func recordEvent(_ name: String, attributes: [String: String] = [:]) {}
    func recordPayload(name: String, body: String, attributes: [String: String] = [:]) {}

    func startSpan(name: String, operation: String) -> any TelemetrySpan {
        Self.spanFactories[name]?(signposter) ?? NoopTelemetrySpan()
    }
}

private final class MultiplexTelemetrySpan: TelemetrySpan, @unchecked Sendable {
    private let spans: [any TelemetrySpan]
    private let lock = NSLock()
    private var didFinish = false

    init(spans: [any TelemetrySpan]) {
        self.spans = spans
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return }
        didFinish = true
        spans.forEach { $0.finish() }
    }
}

private final class OSSignpostTelemetrySpan: TelemetrySpan, @unchecked Sendable {
    private let endInterval: () -> Void
    private let lock = NSLock()
    private var didFinish = false

    init(endInterval: @escaping () -> Void) {
        self.endInterval = endInterval
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return }
        didFinish = true
        endInterval()
    }
}

struct CurrentTelemetryProvider: TelemetryProvider {
    func recordError(_ error: Error, attributes: [String: String] = [:]) {
        Telemetry.recordError(error, attributes: attributes)
    }

    func recordEvent(_ name: String, attributes: [String: String] = [:]) {
        Telemetry.recordEvent(name, attributes: attributes)
    }

    func recordPayload(name: String, body: String, attributes: [String: String] = [:]) {
        Telemetry.recordPayload(name: name, body: body, attributes: attributes)
    }

    func startSpan(name: String, operation: String) -> any TelemetrySpan {
        Telemetry.startSpan(name: name, operation: operation)
    }
}

// A real provider implementation must handle its own concurrency.
enum Telemetry {
    nonisolated(unsafe) static var provider: any TelemetryProvider = NoopTelemetryProvider()

    static func recordError(_ error: Error, attributes: [String: String] = [:]) {
        provider.recordError(error, attributes: attributes)
    }

    static func recordEvent(_ name: String, attributes: [String: String] = [:]) {
        provider.recordEvent(name, attributes: attributes)
    }

    static func recordPayload(name: String, body: String, attributes: [String: String] = [:]) {
        provider.recordPayload(name: name, body: body, attributes: attributes)
    }

    static func startSpan(name: String, operation: String) -> any TelemetrySpan {
        provider.startSpan(name: name, operation: operation)
    }

    static func flush() {
        (provider as? any FlushableTelemetryProvider)?.flush()
    }
}
