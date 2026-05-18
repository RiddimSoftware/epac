import Foundation
import Testing

struct CalendarSubscriptionRemovalTests {

	@Test func iOSAppDoesNotExposeHostedHouseCalendarSubscription() throws {
		let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let appRoot = testsDirectory.deletingLastPathComponent().appendingPathComponent("epac")
		let forbiddenTerms = [
			"house.ics",
			"calendarHouse",
			"subscriptionURL",
			"copySubscription",
			"copiedSubscription"
		]

		let enumerator = try #require(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
		let scannedFiles = (enumerator.allObjects as? [URL] ?? [])
			.filter { ["swift", "strings"].contains($0.pathExtension) }

		let violations = try scannedFiles.flatMap { fileURL in
			let source = try String(contentsOf: fileURL, encoding: .utf8)
			return forbiddenTerms.compactMap { term in
				source.contains(term) ? "\(fileURL.lastPathComponent): \(term)" : nil
			}
		}

		#expect(violations.isEmpty, "Hosted calendar subscription references remain: \(violations.joined(separator: ", "))")
	}
}
