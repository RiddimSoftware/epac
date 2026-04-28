//
//  ReconciliationCallsTests.swift
//  epacTests
//
//  Created on 2026-04-28.
//

@testable import epac
import XCTest

final class ReconciliationCallsTests: XCTestCase {
	func testReconciliationDataMeetsAcceptanceCriteria() throws {
		let dataset = try loadDataset()

		XCTAssertEqual(dataset.calls.count, 94)
		XCTAssertEqual(Set(dataset.calls.map(\.number)), Set(1...94))
		XCTAssertEqual(dataset.metadata.yellowheadReportYear, 2023)
		XCTAssertTrue(dataset.metadata.yellowheadReportUrl.hasPrefix("https://yellowheadinstitute.org/"))
		XCTAssertTrue(dataset.metadata.trcPublicationUrl.hasPrefix("https://publications.gc.ca/"))

		let themes = Set(dataset.calls.map(\.theme))
		XCTAssertTrue(themes.isSuperset(of: Set([
			.childWelfare,
			.education,
			.languageAndCulture,
			.health,
			.justice
		])))

		let statuses = Set(dataset.calls.map(\.status))
		XCTAssertTrue(statuses.contains(.notStarted))
		XCTAssertTrue(statuses.contains(.inProgress))
		XCTAssertTrue(statuses.contains(.completed))

		for call in dataset.calls {
			XCTAssertFalse(call.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(call.callText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(call.responsibleParty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(call.statusSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertTrue(call.statusAttribution.localizedCaseInsensitiveContains("Yellowhead Institute 2023"))
			XCTAssertTrue(call.trcSource.url.hasPrefix("https://"))
			XCTAssertTrue(call.statusSource.url.hasPrefix("https://www.cbc.ca/newsinteractives/beyond-94/"))
			XCTAssertTrue(call.primarySource.url.hasPrefix("https://"))
			XCTAssertGreaterThanOrEqual(call.statusHistory.count, 2)
		}
	}

	func testStatusToneMapping() {
		XCTAssertEqual(ReconciliationStatus.completed.tone, .green)
		XCTAssertEqual(ReconciliationStatus.inProgress.tone, .amber)
		XCTAssertEqual(ReconciliationStatus.notStarted.tone, .red)
	}

	private func loadDataset() throws -> ReconciliationCallsDataset {
		let data = try Data(contentsOf: dataURL())
		return try ReconciliationCallsRepository.decode(data)
	}

	private func dataURL() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("data/reconciliation-calls.json")
	}
}
