import Foundation

protocol TelemetrySpan {
    func finish()
}

protocol TelemetryProvider {
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
