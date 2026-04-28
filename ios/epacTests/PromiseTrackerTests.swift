//
//  PromiseTrackerTests.swift
//  epacTests
//
//  Created on 2026-04-28.
//

import XCTest
@testable import epac

final class PromiseTrackerTests: XCTestCase {
	func testPromiseTrackerDataMeetsAcceptanceCriteria() throws {
		let dataset = try loadDataset()

		XCTAssertGreaterThanOrEqual(dataset.commitments.count, 20)
		XCTAssertEqual(dataset.metadata.governingParty, "Liberal Party of Canada")
		XCTAssertTrue(dataset.metadata.reviewPolicy.localizedCaseInsensitiveContains("pull request"))
		XCTAssertTrue(dataset.metadata.platformUrl.hasPrefix("https://liberal.ca/"))
		XCTAssertTrue(dataset.metadata.governmentVerificationUrl.hasPrefix("https://www.pm.gc.ca/"))

		for commitment in dataset.commitments {
			XCTAssertFalse(commitment.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(commitment.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(commitment.promise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(commitment.statusRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertFalse(commitment.source.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			XCTAssertTrue(commitment.source.url.hasPrefix("https://liberal.ca/"))
			XCTAssertFalse(commitment.evidence.isEmpty)

			for evidence in commitment.evidence {
				XCTAssertFalse(evidence.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				XCTAssertFalse(evidence.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				XCTAssertFalse(evidence.citation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				XCTAssertTrue(evidence.url.hasPrefix("https://budget.canada.ca/") || evidence.url.hasPrefix("https://www.parl.ca/"))
				XCTAssertNotNil(URL(string: evidence.url))
			}
		}
	}

	func testPromiseTrackerStatusToneMapping() {
		XCTAssertEqual(PromiseTrackerStatus.kept.tone, .green)
		XCTAssertEqual(PromiseTrackerStatus.inProgress.tone, .amber)
		XCTAssertEqual(PromiseTrackerStatus.partiallyKept.tone, .amber)
		XCTAssertEqual(PromiseTrackerStatus.notStarted.tone, .red)
		XCTAssertEqual(PromiseTrackerStatus.broken.tone, .red)
	}

	func testPromiseTrackerIncludesReviewableStatusCoverage() throws {
		let statuses = Set(try loadDataset().commitments.map(\.status))

		XCTAssertTrue(statuses.contains(.kept))
		XCTAssertTrue(statuses.contains(.inProgress))
		XCTAssertTrue(statuses.contains(.partiallyKept))
	}

	private func loadDataset() throws -> PromiseTrackerDataset {
		let data = try Data(contentsOf: dataURL())
		return try PromiseTrackerRepository.decode(data)
	}

	private func dataURL() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("data/promise-tracker.json")
	}
}
