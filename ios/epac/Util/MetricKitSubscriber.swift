//
//  MetricKitSubscriber.swift
//  epac
//

import MetricKit
import Foundation

// Subscribes to MetricKit payloads delivered once per day (on device)
// and logs the full JSON representation. In production this is the
// natural place to forward metrics to a telemetry backend.
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
			let period = "\(payload.timeStampBegin.formatted(date: .abbreviated, time: .omitted))–\(payload.timeStampEnd.formatted(date: .abbreviated, time: .omitted))"
			if let json = try? JSONSerialization.jsonObject(with: payload.jsonRepresentation()) {
				Log.debug("[MetricKit] Period \(period): \(json)")
			}
		}
	}

	func didReceive(_ payloads: [MXDiagnosticPayload]) {
		for payload in payloads {
			if let json = try? JSONSerialization.jsonObject(with: payload.jsonRepresentation()) {
				Log.debug("[MetricKit] Diagnostic payload: \(json)")
			}
		}
	}
}
