//
//  PerformanceLaunchHarness.swift
//  epac
//

import Foundation

enum PerformanceLaunchHarness {
	static let fetchTranscriptArgument = "-EPAC_PERF_FETCH_TRANSCRIPT"
	static let completedAccessibilityIdentifier = "performance-harness-completed"

	private static var shouldRunFetchTranscript: Bool {
		AppRuntime.isRunningTests && CommandLine.arguments.contains(fetchTranscriptArgument)
	}

	@MainActor
	@discardableResult
	static func runIfRequested(fetch: Fetch, repository: any HansardRepository) async -> Bool {
		guard shouldRunFetchTranscript else { return false }

		do {
			let fixture = try fetchTranscriptFixture()
			try await fetch.ingestHansard(xml: fixture.xml)
			_ = try await LoadDailyHansard(repository: repository).execute(
				jurisdiction: .federal,
				sittingDate: fixture.sittingDate
			)
			return true
		} catch {
			Log.error("PerformanceLaunchHarness.fetchTranscript failed: \(error)")
			return false
		}
	}

	private static func fetchTranscriptFixture() throws -> (xml: String, sittingDate: Date) {
		let fixtureName = EvidenceFixtureSeed.defaultFixtureName
		guard let xml = EvidenceFixtureSeed.loadFixtureXML(named: fixtureName) else {
			throw PerformanceLaunchHarnessError.missingFixture(name: fixtureName)
		}
		guard let dateString = EvidenceFixtureSeed.fixtureDates[fixtureName],
		      let sittingDate = fixtureDate(from: dateString) else {
			throw PerformanceLaunchHarnessError.invalidFixtureDate(name: fixtureName)
		}
		return (xml, sittingDate)
	}

	private static func fixtureDate(from string: String) -> Date? {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.date(from: string)
	}
}

private enum PerformanceLaunchHarnessError: Error {
	case missingFixture(name: String)
	case invalidFixtureDate(name: String)
}
