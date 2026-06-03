//
//  PerfInstrumentation.swift
//  epac
//

import OSLog
import SwiftUI

enum PerfInstrumentation {
	enum Interval {
		case homeFeedView
		case speechView

		var name: StaticString {
			switch self {
			case .homeFeedView:
				return "HomeFeedView"
			case .speechView:
				return "SpeechView"
			}
		}
	}

	private static let fallbackSubsystem = "com.riddimsoftware.epac"
	private static let category = "Performance"
	private static let signposter = OSSignposter(
		subsystem: Bundle.main.bundleIdentifier ?? fallbackSubsystem,
		category: category
	)

	static func beginAnimationInterval(_ interval: Interval) -> OSSignpostIntervalState {
		signposter.beginAnimationInterval(interval.name)
	}

	static func endInterval(_ interval: Interval, state: OSSignpostIntervalState) {
		signposter.endInterval(interval.name, state)
	}
}

private struct PerfSignpostIntervalModifier: ViewModifier {
	let interval: PerfInstrumentation.Interval
	@State private var intervalState: OSSignpostIntervalState?

	func body(content: Content) -> some View {
		content
			.onAppear {
				guard intervalState == nil else { return }
				intervalState = PerfInstrumentation.beginAnimationInterval(interval)
			}
			.onDisappear {
				guard let state = intervalState else { return }
				PerfInstrumentation.endInterval(interval, state: state)
				intervalState = nil
			}
	}
}

extension View {
	func perfSignpostInterval(_ interval: PerfInstrumentation.Interval) -> some View {
		modifier(PerfSignpostIntervalModifier(interval: interval))
	}
}
