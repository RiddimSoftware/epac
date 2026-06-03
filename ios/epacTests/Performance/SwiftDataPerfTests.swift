@testable import epac
import Foundation
import SwiftData
import XCTest

@MainActor
final class SwiftDataPerfTests: XCTestCase {
	private static let readStartDate = date(year: 2021, month: 1, day: 1)
	private static let readEndDate = date(year: 2026, month: 12, day: 31)
	private static let migrationSeedDate = date(year: 2024, month: 2, day: 1)

	override func setUp() {
		super.setUp()
		continueAfterFailure = false
		executionTimeAllowance = 120
	}

	func testSittingCalendarReadMetrics() throws {
		let container = try Self.makeLatestInMemoryContainer()
		let context = ModelContext(container)
		try Self.seedSittingCalendars(in: context)
		let options = Self.measureOptions(iterations: 5)
		var measuredCount = 0

		measure(
			metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
			options: options
		) {
			do {
				startMeasuring()
				let dates = try Self.cachedSittingDates(
					in: context,
					from: Self.readStartDate,
					through: Self.readEndDate
				)
				stopMeasuring()
				measuredCount = dates.count
			} catch {
				stopMeasuring()
				XCTFail("SwiftData sitting-date read failed: \(error)")
			}
		}

		XCTAssertEqual(measuredCount, 1_080)
	}

	func testEarliestSchemaMigrationOpenMetrics() throws {
		let fixtureStoreURL = try Self.makeSchemaV3FixtureStore()
		defer {
			try? FileManager.default.removeItem(at: fixtureStoreURL.deletingLastPathComponent())
		}
		let options = Self.measureOptions(iterations: 3)
		var migratedHansardCount = 0
		var migratedCalendarCount = 0

		measure(
			metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric(), XCTStorageMetric()],
			options: options
		) {
			var didStartMeasuring = false
			var storeURL: URL?
			do {
				let copiedStoreURL = try Self.copyStoreFixture(from: fixtureStoreURL)
				storeURL = copiedStoreURL
				startMeasuring()
				didStartMeasuring = true
				let container = try ModelContainer(
					for: Schema(versionedSchema: SchemaV10.self),
					migrationPlan: EpacMigrationPlan.self,
					configurations: [ModelConfiguration(url: copiedStoreURL)]
				)
				let context = ModelContext(container)
				migratedHansardCount = try context.fetchCount(FetchDescriptor<Hansard>())
				migratedCalendarCount = try context.fetchCount(FetchDescriptor<SittingCalendar>())
				stopMeasuring()
				didStartMeasuring = false
			} catch {
				if didStartMeasuring {
					stopMeasuring()
				}
				XCTFail("SwiftData migration open failed: \(error)")
			}
			if let storeURL {
				try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
			}
		}

		XCTAssertEqual(migratedHansardCount, 1)
		XCTAssertEqual(migratedCalendarCount, 1)
	}

	private static func makeLatestInMemoryContainer() throws -> ModelContainer {
		try ModelContainer(
			for: Schema(versionedSchema: SchemaV10.self),
			migrationPlan: EpacMigrationPlan.self,
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
	}

	private static func seedSittingCalendars(in context: ModelContext) throws {
		for year in 2021...2026 {
			context.insert(SittingCalendar(year: year, sittings: sittingDates(for: year)))
		}
		try context.save()
	}

	private static func sittingDates(for year: Int) -> [Date] {
		(1...12).flatMap { month in
			(1...15).map { day in
				date(year: year, month: month, day: day)
			}
		}
	}

	private static func cachedSittingDates(
		in context: ModelContext,
		from startDate: Date,
		through endDate: Date
	) throws -> [Date] {
		var dates: [Date] = []
		for year in years(from: startDate, through: endDate) {
			let descriptor = FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })
			if let calendar = try context.fetch(descriptor).first {
				dates.append(contentsOf: calendar.sittings)
			}
		}
		return dates
			.filter { startDate <= $0 && $0 <= endDate }
			.removingDuplicates()
			.sorted()
	}

	private static func years(from startDate: Date, through endDate: Date) -> [Int] {
		let calendar = Calendar(identifier: .gregorian)
		let startYear = calendar.component(.year, from: startDate)
		let endYear = calendar.component(.year, from: endDate)
		return Array(startYear...endYear)
	}

	private static func makeSchemaV3FixtureStore() throws -> URL {
		let storeURL = temporaryStoreURL(prefix: "epac-schema-v3-fixture")
		try FileManager.default.createDirectory(
			at: storeURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)

		do {
			let container = try ModelContainer(
				for: Schema(versionedSchema: SchemaV3.self),
				configurations: [ModelConfiguration(url: storeURL)]
			)
			let context = ModelContext(container)
			context.insert(SchemaV3.SittingCalendar(year: 2024, sittings: [migrationSeedDate]))
			context.insert(Self.schemaV3Hansard())
			try context.save()
		}

		return storeURL
	}

	private static func schemaV3Hansard() -> SchemaV3.Hansard {
		let messages = (1...20).map { index in
			SchemaV3.SpeechMessage(
				firstName: "Alex",
				lastName: "Sample",
				partyAbbreviation: "Lib.",
				ridingName: "Ottawa Centre",
				hansardID: "schema-v3-message-\(index)",
				content: "Fixture intervention paragraph \(index).",
				timestamp: migrationSeedDate
			)
		}
		let speech = SchemaV3.Speech(
			messages: messages,
			hansardID: "schema-v3-speech",
			date: migrationSeedDate,
			title: "Oral Questions"
		)
		let subject = SchemaV3.SubjectOfBusiness(
			title: "Oral Questions",
			hansardID: "schema-v3-subject",
			speeches: [speech]
		)
		let order = SchemaV3.OrderOfBusiness(
			hansardID: "schema-v3-order",
			catchline: "Oral Questions",
			subjects: [subject]
		)
		return SchemaV3.Hansard(
			date: migrationSeedDate,
			hansardID: "schema-v3-hansard",
			parliamentNumber: 44,
			sessionNumber: 1,
			orders: [order]
		)
	}

	private static func copyStoreFixture(from sourceStoreURL: URL) throws -> URL {
		let destinationStoreURL = temporaryStoreURL(prefix: "epac-schema-v3-migration")
		try FileManager.default.copyItem(
			at: sourceStoreURL.deletingLastPathComponent(),
			to: destinationStoreURL.deletingLastPathComponent()
		)
		return destinationStoreURL
	}

	private static func temporaryStoreURL(prefix: String) -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
			.appendingPathComponent("epac.store")
	}

	private static func measureOptions(iterations: Int) -> XCTMeasureOptions {
		let options = XCTMeasureOptions.default
		options.iterationCount = iterations
		options.invocationOptions = [.manuallyStart, .manuallyStop]
		return options
	}

	private static func date(year: Int, month: Int, day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
	}
}

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
