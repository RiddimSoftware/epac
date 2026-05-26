//
//  MetricKitSubscriber.swift
//  epac
//

import Foundation
import MetricKit

// Subscribes to MetricKit payloads delivered once per day (on device)
// and forwards the full JSON representation through first-party telemetry.
//
// Metrics that land here include: app launch time, hang rate, CPU time,
// memory peak, disk writes, scroll hitch rate, and battery drain.
// Diagnostics include: crashes, hangs, CPU exceptions, and disk writes.
final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
	static let shared = MetricKitSubscriber()
	private override init() { super.init() }

	func start() {
		MXMetricManager.shared.add(self)
		Log.debug("[MetricKit] Subscriber registered")
	}

	// MARK: - MXMetricManagerSubscriber

	func didReceive(_ payloads: [MXMetricPayload]) {
		for payload in payloads {
			MetricKitTelemetryForwarder.recordPayload(
				name: "metrickit.metric",
				jsonData: payload.jsonRepresentation(),
				periodBegin: payload.timeStampBegin,
				periodEnd: payload.timeStampEnd
			)
		}
	}

	func didReceive(_ payloads: [MXDiagnosticPayload]) {
		for payload in payloads {
			MetricKitTelemetryForwarder.recordPayload(
				name: "metrickit.diagnostic",
				jsonData: payload.jsonRepresentation(),
				periodBegin: payload.timeStampBegin,
				periodEnd: payload.timeStampEnd
			)
		}
	}
}

enum MetricKitTelemetryForwarder {
	private static let maxBodyKilobytes = 64
	private static let bytesPerKilobyte = 1_024
	private static let maxBodyBytes = maxBodyKilobytes * bytesPerKilobyte

	static func recordPayload(name: String, jsonData: Data, periodBegin: Date, periodEnd: Date) {
		let body = truncatedBody(from: jsonData)
		let formatter = ISO8601DateFormatter()
		var attributes = [
			"period_begin": formatter.string(from: periodBegin),
			"period_end": formatter.string(from: periodEnd)
		]
		if body.droppedBytes > 0 {
			attributes["truncated_bytes"] = "\(body.droppedBytes)"
		}

		Telemetry.recordPayload(name: name, body: body.value, attributes: attributes)
	}

	private static func truncatedBody(from data: Data) -> (value: String, droppedBytes: Int) {
		guard data.count > maxBodyBytes else {
			return (String(data: data, encoding: .utf8) ?? "", 0)
		}

		var prefix = data.prefix(maxBodyBytes)
		while !prefix.isEmpty, String(data: prefix, encoding: .utf8) == nil {
			prefix = prefix.dropLast()
		}

		return (String(data: prefix, encoding: .utf8) ?? "", data.count - prefix.count)
	}
}
