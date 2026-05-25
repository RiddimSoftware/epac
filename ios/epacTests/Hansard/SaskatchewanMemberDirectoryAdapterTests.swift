@testable import epac
import Foundation
import SwiftData
import Testing

struct SaskatchewanMemberDirectoryAdapterTests {
	@Test func parsesSaskatchewanRosterFixture() throws {
		let members = try SaskatchewanMemberDirectoryAdapter().parse(html: fixtureHTML())

		#expect(members.count == 61)
		let carlaBeck = try #require(members.first { $0.name == "Carla Beck" })
		#expect(carlaBeck.jurisdiction == .saskatchewan)
		#expect(carlaBeck.party == .newdemocratic)
		#expect(carlaBeck.riding == "Regina Lakeview")
		#expect(carlaBeck.hillPhone == nil)
		#expect(carlaBeck.constituencyPhone == "306-522-1333")
		#expect(carlaBeck.email == "reginalakeview@ndpcaucus.sk.ca")
		#expect(carlaBeck.constituencyAddress == "2213 Broad Street, Regina, SK S4P 1Y7")
		#expect(carlaBeck.photoURL.absoluteString == "https://www.legassembly.sk.ca/img/logo.png")

		let bettyNippiAlbright = try #require(members.first { $0.name == "Betty Nippi-Albright" })
		#expect(bettyNippiAlbright.party == .independent)

		let scottMoe = try #require(members.first { $0.name == "Scott Moe" })
		#expect(scottMoe.party == .saskatchewanParty)
	}

	@Test func missingEmailParsesAsNil() throws {
		let html = try fixtureHTML().replacingOccurrences(
			of: #"<a href="mailto:reginalakeview@ndpcaucus.sk.ca">reginalakeview@ndpcaucus.sk.ca</a>"#,
			with: ""
		)

		let members = try SaskatchewanMemberDirectoryAdapter().parse(html: html)
		let carlaBeck = try #require(members.first { $0.name == "Carla Beck" })

		#expect(carlaBeck.email == nil)
		#expect(carlaBeck.constituencyPhone == "306-522-1333")
	}

	@Test func migrationSeedsFederalJurisdictionAndDirectoryKey() throws {
		let storeURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("SaskatchewanMemberDirectoryAdapterTests-\(UUID().uuidString)")
			.appendingPathComponent("epac.store")
		defer {
			try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
		}
		try FileManager.default.createDirectory(
			at: storeURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)

		let oldConfig = ModelConfiguration(url: storeURL)
		do {
			let oldContainer = try ModelContainer(
				for: Schema(versionedSchema: SchemaV8.self),
				configurations: [oldConfig]
			)
			let oldContext = ModelContext(oldContainer)
			oldContext.insert(
				SchemaV5.ParliamentMember(
					name: "Jeremy Harrison",
					lastName: "Harrison",
					firstName: "Jeremy",
					photoURL: URL(string: "https://example.com/jeremy.jpg")!,
					riding: "Meadow Lake",
					province: .Saskatchewan,
					party: .conservative,
					memberID: 123
				)
			)
			try oldContext.save()
		}

		let newContainer = try ModelContainer(
			for: Schema(versionedSchema: SchemaV10.self),
			migrationPlan: EpacMigrationPlan.self,
			configurations: [ModelConfiguration(url: storeURL)]
		)
		let context = ModelContext(newContainer)
		let members = try context.fetch(FetchDescriptor<ParliamentMember>())
		let member = try #require(members.onlyElement)

		#expect(member.name == "Jeremy Harrison")
		#expect(member.jurisdiction == .federal)
		#expect(member.directoryKey == "federal::Jeremy Harrison")
		#expect(member.memberID == 123)
	}

	private func fixtureHTML() throws -> String {
		try String(contentsOf: fixtureURL(), encoding: .utf8)
	}

	private func fixtureURL() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/Saskatchewan/Members/mla-contact-information.html")
	}
}

private extension Array {
	var onlyElement: Element? {
		count == 1 ? first : nil
	}
}
