@testable import epac
import Foundation
import Testing

struct NovaScotiaMemberDirectoryAdapterTests {
	@Test func parsesNovaScotiaRosterFixture() throws {
		let members = try NovaScotiaMemberDirectoryAdapter().parse(html: fixtureHTML())

		#expect(members.count == 55)
		let claudiaChender = try #require(members.first { $0.name == "Claudia Chender" })
		#expect(claudiaChender.jurisdiction == .novaScotia)
		#expect(claudiaChender.province == .NS)
		#expect(claudiaChender.party == .newdemocratic)
		#expect(claudiaChender.riding == "Dartmouth South")
		#expect(claudiaChender.email == nil)
		#expect(claudiaChender.constituencyPhone == nil)
		#expect(claudiaChender.websiteURL?.absoluteString == "https://nslegislature.ca/members/profiles/claudia-chender")
		#expect(claudiaChender.photoURL.absoluteString.contains("ClaudiaChender-Square.jpg"))

		let timHouston = try #require(members.first { $0.name == "Tim Houston" })
		#expect(timHouston.party == .conservative)
		#expect(timHouston.riding == "Pictou East")
	}

	@Test func parsesProfileContactDetails() throws {
		let contact = try NovaScotiaMemberDirectoryAdapter().parseContactDetails(html: Self.profileHTML(email: true))

		#expect(contact.email == "claudiachender@nsmla.ca")
		#expect(contact.constituencyPhone == "902-406-2301")
		#expect(contact.hillPhone == "902-424-4134")
		#expect(contact.constituencyAddress == "33 Ochterloney Street, Suite 360, Dartmouth, NS, B2Y 4P5")
	}

	@Test func missingEmailStillIngestsMember() async throws {
		let adapter = NovaScotiaMemberDirectoryAdapter(
			fetchData: { url in
				if url.path == "/members/profiles/65" {
					return Data(Self.singleMemberRosterHTML.utf8)
				}
				return Data(Self.profileHTML(email: false).utf8)
			},
			sleep: { _ in },
			profileRequestDelayNanoseconds: 0
		)

		let members = try await adapter.fetchMembers()
		let member = try #require(members.onlyElement)

		#expect(member.name == "Claudia Chender")
		#expect(member.email == nil)
		#expect(member.constituencyPhone == "902-406-2301")
		#expect(member.contactFetched)
	}

	private func fixtureHTML() throws -> String {
		try String(contentsOf: fixtureURL(), encoding: .utf8)
	}

	private func fixtureURL() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/NovaScotia/Members/profiles-65.html")
	}

	private static let singleMemberRosterHTML = """
	<html><body>
	<div class="view-mla-profile-listing">
		<div class="views-row">
			<div class="views-field views-field-field-thumbnail">
				<div class="field-content">
					<img src="https://nslegislature.ca/sites/default/files/mla-thumbnails/ClaudiaChender.jpg" />
				</div>
			</div>
			<div class="views-field views-field-field-last-name">
				<div class="field-content"><a href="/members/profiles/claudia-chender/history">Chender, Claudia</a></div>
			</div>
			<div class="views-field views-field-field-party">
				<div class="field-content"><span class="party-name">NDP</span></div>
			</div>
			<div class="views-field views-field-field-constituency-name">
				<div class="field-content">Dartmouth South</div>
			</div>
		</div>
	</div>
	</body></html>
	"""

	private static func profileHTML(email: Bool) -> String {
		let emailLine = email ? #"E-mail: <a href="mailto:claudiachender@nsmla.ca">claudiachender@nsmla.ca</a>"# : ""
		return """
		<html><body>
		<div class="panel-pane pane-dsc mla-current-profile-contact">
			<h2>Contact details</h2><h4>Constituency office</h4>
			<p>
			Civic address:
			<br>33 Ochterloney Street<br />
			Suite 360<br />
			Dartmouth, NS<br />
			B2Y 4P5
			</p>
			<p>
			Phone: <a href="tel:+19024062301">902-406-2301</a>
			<br>
			\(emailLine)
			</p>
			<h4>Business address</h4>
			<p>
			NDP Caucus Office<br />
			BMO Building<br />
			5151 George Street, Suite 1402<br />
			Halifax, NS B3J 1M5
			</p>
			<p>
			Phone: <a href="tel:+19024244134">902-424-4134</a>
			</p>
		</div>
		</body></html>
		"""
	}
}

private extension Array {
	var onlyElement: Element? {
		count == 1 ? first : nil
	}
}
