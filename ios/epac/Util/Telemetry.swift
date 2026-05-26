import Foundation

protocol TelemetrySpan {
    func finish()
}

protocol TelemetryProvider {
    func recordError(_ error: Error, attributes: [String: String])
    func recordEvent(_ name: String, attributes: [String: String])
    func startSpan(name: String, operation: String) -> any TelemetrySpan
}

struct NoopTelemetrySpan: TelemetrySpan {
    func finish() {}
}

struct NoopTelemetryProvider: TelemetryProvider {
    func recordError(_ error: Error, attributes: [String: String] = [:]) {}
    func recordEvent(_ name: String, attributes: [String: String] = [:]) {}
    func startSpan(name: String, operation: String) -> any TelemetrySpan { NoopTelemetrySpan() }
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

    static func startSpan(name: String, operation: String) -> any TelemetrySpan {
        provider.startSpan(name: name, operation: operation)
    }
}
