//
//  NetworkMonitor.swift
//  epac
//

import Network
import Observation

// Monitors network path status using NWPathMonitor and publishes
// isConnected via @Observable so SwiftUI views re-render automatically.
// Start monitoring by calling start(); the monitor runs on a dedicated
// background queue and dispatches updates to the main actor.
@MainActor
@Observable
final class NetworkMonitor {
	private(set) var isConnected = true

	private let monitor = NWPathMonitor()
	private let queue = DispatchQueue(label: "net.dinglebox.cabinetdoor.networkMonitor")
	private var isStarted = false

	func start() {
		guard !isStarted else { return }
		isStarted = true
		monitor.pathUpdateHandler = { [weak self] path in
			let connected = path.status == .satisfied
			Task { @MainActor [weak self] in
				self?.isConnected = connected
			}
		}
		monitor.start(queue: queue)
	}
}
