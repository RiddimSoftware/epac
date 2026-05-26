//
//  BackendTelemetryProvider.swift
//  epac
//

import Foundation

private let backendTelemetryProviderPIIPolicyNotice: Void = {
    Log.debug("BackendTelemetryProvider — attributes / messages / bodies must not include PII; callers are responsible.")
}()

final class BackendTelemetryProvider: TelemetryProvider, FlushableTelemetryProvider, @unchecked Sendable {
    private enum Constants {
        static let batchSize = 30
        static let maxQueueCount = 300
        static let flushInterval: TimeInterval = 10
        static let maxEventNameBytes = 128
        static let maxOperationBytes = 64
        static let maxMessageBytes = 512
        static let maxAttributeKeyBytes = 32
        static let maxAttributeValueBytes = 256
        static let maxAttributeCount = 16
        static let maxAppVersionBytes = 32
        static let maxOSVersionBytes = 32
        static let maxPayloadBodyKilobytes = 64
        static let bytesPerKilobyte = 1_024
        static let maxPayloadBodyBytes = maxPayloadBodyKilobytes * bytesPerKilobyte
        static let millisecondsPerSecond = 1_000
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let telemetryPath = "api/v1/telemetry"
        static let deviceIDKey = "epac.telemetry.deviceID"
    }

    private let networkService: NetworkService
    private let baseURL: URL
    private let userDefaults: UserDefaults
    private let appVersion: String
    private let osVersion: String
    private let uuidProvider: @Sendable () -> String
    private let dateProvider: @Sendable () -> Date
    private let batchSize: Int
    private let maxQueueCount: Int
    private let flushInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.riddimsoftware.epac.backend-telemetry")

    private var queuedEvents: [BackendTelemetryEvent] = []
    private var scheduledFlush: DispatchWorkItem?
    private var smallFlushInFlight = false
    private var lastFlushDate: Date

    init(
        networkService: NetworkService = .shared,
        baseURL: URL = BackendConfig.shared.baseURL,
        userDefaults: UserDefaults = .standard,
        appVersion: String = BackendTelemetryProvider.defaultAppVersion(),
        osVersion: String = BackendTelemetryProvider.defaultOSVersion(),
        uuidProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        batchSize: Int = Constants.batchSize,
        maxQueueCount: Int = Constants.maxQueueCount,
        flushInterval: TimeInterval = Constants.flushInterval
    ) {
        _ = backendTelemetryProviderPIIPolicyNotice
        self.networkService = networkService
        self.baseURL = baseURL
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.uuidProvider = uuidProvider
        self.dateProvider = dateProvider
        self.batchSize = batchSize
        self.maxQueueCount = maxQueueCount
        self.flushInterval = flushInterval
        self.lastFlushDate = dateProvider()
    }

    func recordError(_ error: Error, attributes: [String: String] = [:]) {
        let nsError = error as NSError
        var eventAttributes = attributes
        eventAttributes["error_domain"] = nsError.domain
        eventAttributes["error_code"] = "\(nsError.code)"

        enqueueSmallEvent(
            BackendTelemetryEvent(
                type: .error,
                name: Self.normalizedName(nsError.domain, fallback: "error"),
                message: Self.truncated(error.localizedDescription, maxBytes: Constants.maxMessageBytes),
                attributes: Self.normalizedAttributes(eventAttributes),
                ts: dateProvider()
            )
        )
    }

    func recordEvent(_ name: String, attributes: [String: String] = [:]) {
        enqueueSmallEvent(
            BackendTelemetryEvent(
                type: .event,
                name: Self.normalizedName(name, fallback: "event"),
                attributes: Self.normalizedAttributes(attributes),
                ts: dateProvider()
            )
        )
    }

    func recordPayload(name: String, body: String, attributes: [String: String] = [:]) {
        let truncatedBody = Self.truncatedBody(body)
        var eventAttributes = attributes
        if truncatedBody.droppedBytes > 0 {
            eventAttributes["truncated_bytes"] = "\(truncatedBody.droppedBytes)"
        }

        sendBatch([
            BackendTelemetryEvent(
                type: .payload,
                name: Self.normalizedName(name, fallback: "payload"),
                body: truncatedBody.body,
                attributes: Self.normalizedAttributes(eventAttributes),
                ts: dateProvider()
            )
        ])
    }

    func startSpan(name: String, operation: String) -> any TelemetrySpan {
        BackendTelemetrySpan(
            name: name,
            operation: operation,
            startDate: dateProvider()
        ) { [weak self] name, operation, startDate, finishDate in
            self?.recordSpan(name: name, operation: operation, startDate: startDate, finishDate: finishDate)
        }
    }

    func flush() {
        queue.async { [weak self] in
            self?.flushSmallEventsLocked()
        }
    }

    private func recordSpan(name: String, operation: String, startDate: Date, finishDate: Date) {
        let duration = max(0, Int(finishDate.timeIntervalSince(startDate) * Double(Constants.millisecondsPerSecond)))
        enqueueSmallEvent(
            BackendTelemetryEvent(
                type: .span,
                name: Self.normalizedName(name, fallback: "span"),
                operation: Self.truncated(operation, maxBytes: Constants.maxOperationBytes),
                durationMs: duration,
                attributes: [:],
                ts: finishDate
            )
        )
    }

    private func enqueueSmallEvent(_ event: BackendTelemetryEvent) {
        queue.async { [weak self] in
            self?.enqueueSmallEventLocked(event)
        }
    }

    private func enqueueSmallEventLocked(_ event: BackendTelemetryEvent) {
        if queuedEvents.count >= maxQueueCount {
            queuedEvents.removeFirst()
            Log.debug("[Telemetry] Dropped oldest queued event after reaching \(maxQueueCount) event cap")
        }

        queuedEvents.append(event)

        let now = dateProvider()
        if queuedEvents.count >= batchSize || now.timeIntervalSince(lastFlushDate) >= flushInterval {
            flushSmallEventsLocked()
            return
        }

        scheduleFlushLocked(after: max(0, flushInterval - now.timeIntervalSince(lastFlushDate)))
    }

    private func scheduleFlushLocked(after delay: TimeInterval) {
        scheduledFlush?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushSmallEventsLocked()
        }
        scheduledFlush = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func flushSmallEventsLocked() {
        guard !smallFlushInFlight else { return }
        guard !queuedEvents.isEmpty else {
            scheduledFlush?.cancel()
            scheduledFlush = nil
            return
        }

        let events = queuedEvents
        queuedEvents.removeAll(keepingCapacity: true)
        scheduledFlush?.cancel()
        scheduledFlush = nil
        smallFlushInFlight = true

        sendBatch(events) { [weak self] in
            self?.queue.async { [weak self] in
                self?.completeSmallFlushLocked()
            }
        }
    }

    private func completeSmallFlushLocked() {
        smallFlushInFlight = false
        lastFlushDate = dateProvider()

        guard !queuedEvents.isEmpty else { return }
        if queuedEvents.count >= batchSize {
            flushSmallEventsLocked()
        } else {
            scheduleFlushLocked(after: flushInterval)
        }
    }

    private func sendBatch(_ events: [BackendTelemetryEvent], completion: (@Sendable () -> Void)? = nil) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                completion?()
                return
            }

            await self.post(events: events)
            completion?()
        }
    }

    private func post(events: [BackendTelemetryEvent]) async {
        do {
            let body = BackendTelemetryRequest(
                deviceID: deviceID(),
                appVersion: Self.truncated(appVersion, maxBytes: Constants.maxAppVersionBytes),
                osVersion: Self.truncated(osVersion, maxBytes: Constants.maxOSVersionBytes),
                events: events
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            var request = URLRequest(url: baseURL.appending(path: Constants.telemetryPath))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)

            let (_, response) = try await networkService.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Log.debug("[Telemetry] POST /api/v1/telemetry completed without an HTTP response")
                return
            }

            guard Constants.successStatusLowerBound..<Constants.successStatusUpperBound ~= httpResponse.statusCode else {
                Log.debug("[Telemetry] POST /api/v1/telemetry failed with HTTP \(httpResponse.statusCode)")
                return
            }
        } catch {
            Log.debug("[Telemetry] POST /api/v1/telemetry failed: \(error)")
        }
    }

    private func deviceID() -> String {
        if let existing = userDefaults.string(forKey: Constants.deviceIDKey), !existing.isEmpty {
            return existing
        }

        let generated = uuidProvider()
        userDefaults.set(generated, forKey: Constants.deviceIDKey)
        return generated
    }

    private static func defaultAppVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "unknown"
    }

    private static func defaultOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func normalizedName(_ name: String, fallback: String) -> String {
        let candidate = name.isEmpty ? fallback : name
        return truncated(candidate, maxBytes: Constants.maxEventNameBytes)
    }

    private static func normalizedAttributes(_ attributes: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            guard normalized.count < Constants.maxAttributeCount else { break }

            let normalizedKey = truncated(key, maxBytes: Constants.maxAttributeKeyBytes)
            guard normalized[normalizedKey] == nil else { continue }

            normalized[normalizedKey] = truncated(value, maxBytes: Constants.maxAttributeValueBytes)
        }
        return normalized
    }

    private static func truncatedBody(_ body: String) -> (body: String, droppedBytes: Int) {
        let data = Data(body.utf8)
        guard data.count > Constants.maxPayloadBodyBytes else {
            return (body, 0)
        }

        let truncated = truncated(data: data, maxBytes: Constants.maxPayloadBodyBytes)
        return (truncated, data.count - Data(truncated.utf8).count)
    }

    private static func truncated(_ value: String, maxBytes: Int) -> String {
        let data = Data(value.utf8)
        guard data.count > maxBytes else { return value }
        return truncated(data: data, maxBytes: maxBytes)
    }

    private static func truncated(data: Data, maxBytes: Int) -> String {
        var prefix = data.prefix(maxBytes)
        while !prefix.isEmpty, String(data: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(data: prefix, encoding: .utf8) ?? ""
    }
}

final class BackendTelemetrySpan: TelemetrySpan, @unchecked Sendable {
    private let name: String
    private let operation: String
    private let startDate: Date
    private let onFinish: @Sendable (String, String, Date, Date) -> Void
    private let lock = NSLock()
    private var didFinish = false

    init(
        name: String,
        operation: String,
        startDate: Date,
        onFinish: @escaping @Sendable (String, String, Date, Date) -> Void
    ) {
        self.name = name
        self.operation = operation
        self.startDate = startDate
        self.onFinish = onFinish
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return }
        didFinish = true
        onFinish(name, operation, startDate, Date())
    }
}

private struct BackendTelemetryRequest: Encodable {
    let deviceID: String
    let appVersion: String
    let osVersion: String
    let events: [BackendTelemetryEvent]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case events
    }
}

private struct BackendTelemetryEvent: Encodable, Sendable {
    let type: BackendTelemetryEventType
    let name: String
    var operation: String?
    var message: String?
    var durationMs: Int?
    var body: String?
    let attributes: [String: String]
    let ts: Date

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case operation
        case message
        case durationMs = "duration_ms"
        case body
        case attributes
        case ts
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(operation, forKey: .operation)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(body, forKey: .body)
        if !attributes.isEmpty {
            try container.encode(attributes, forKey: .attributes)
        }
        try container.encode(ts, forKey: .ts)
    }
}

private enum BackendTelemetryEventType: String, Encodable, Sendable {
    case error
    case event
    case span
    case payload
}
