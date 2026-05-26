@testable import epac
import Foundation
import Testing

struct OntarioMemberDirectoryAdapterTests {
	@Test func parsesOntarioRosterFixture() throws {
		let members = try OntarioMemberDirectoryAdapter(delayBetweenRequests: {}).parse(
			rosterHTML: rosterFixtureHTML(),
			contactHTML: contactFixtureHTML()
		)

		#expect(members.count == 123)
		let teresaArmstrong = try #require(members.first { $0.name == "Teresa J. Armstrong" })
		#expect(teresaArmstrong.jurisdiction == .ontario)
		#expect(teresaArmstrong.party == .newdemocratic)
		#expect(teresaArmstrong.riding == "London—Fanshawe")
		#expect(teresaArmstrong.province == .Ontario)
		#expect(teresaArmstrong.hillPhone == nil)
		#expect(teresaArmstrong.constituencyPhone == "519-668-1104")
		#expect(teresaArmstrong.email == "tarmstrong-co@ndp.on.ca")
		#expect(teresaArmstrong.constituencyAddress == "155 Clarke Rd., London, ON N5W 5C9")
		#expect(teresaArmstrong.websiteURL?.absoluteString == "https://www.ola.org/en/members/all/teresa-j-armstrong")
		#expect(teresaArmstrong.photoURL.absoluteString.contains("teresa_armstrong"))

		let dougFord = try #require(members.first { $0.name == "Hon. Doug Ford" })
		#expect(dougFord.party == .conservative)
		#expect(dougFord.firstName == "Doug")
		#expect(dougFord.lastName == "Ford")

		let stephanieBowman = try #require(members.first { $0.name == "Stephanie Bowman" })
		#expect(stephanieBowman.party == .liberal)

		let aislinnClancy = try #require(members.first { $0.name == "Aislinn Clancy" })
		#expect(aislinnClancy.party == .green)

		let bobbiAnnBrady = try #require(members.first { $0.name == "Bobbi Ann Brady" })
		#expect(bobbiAnnBrady.party == .independent)
	}

	@Test func missingEmailParsesAsNil() throws {
		let contactHTML = try contactFixtureHTML().replacingOccurrences(
			of: #"<a href="mailto:tarmstrong-co@ndp.on.ca">tarmstrong-co@ndp.on.ca</a>"#,
			with: ""
		)

		let members = try OntarioMemberDirectoryAdapter(delayBetweenRequests: {}).parse(
			rosterHTML: rosterFixtureHTML(),
			contactHTML: contactHTML
		)
		let teresaArmstrong = try #require(members.first { $0.name == "Teresa J. Armstrong" })

		#expect(teresaArmstrong.email == nil)
		#expect(teresaArmstrong.constituencyPhone == "519-668-1104")
		#expect(teresaArmstrong.constituencyAddress == "155 Clarke Rd., London, ON N5W 5C9")
	}

	private func rosterFixtureHTML() throws -> String {
		try String(contentsOf: rosterFixtureURL(), encoding: .utf8)
	}

	private func contactFixtureHTML() throws -> String {
		try String(contentsOf: contactFixtureURL(), encoding: .utf8)
	}

	private func rosterFixtureURL() -> URL {
		fixturesDirectory().appendingPathComponent("current.html")
	}

	private func contactFixtureURL() -> URL {
		fixturesDirectory().appendingPathComponent("constituency-contact.html")
	}

	private func fixturesDirectory() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/Ontario/Members")
	}
}
