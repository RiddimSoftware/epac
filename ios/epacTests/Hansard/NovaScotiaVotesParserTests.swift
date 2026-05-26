//
//  NovaScotiaVotesParserTests.swift
//  epacTests
//

@testable import epac
import Foundation
import SwiftData
import Testing

@Suite("Nova Scotia Votes Parser Tests")
struct NovaScotiaVotesParserTests {

	@Test("Parses complete HTML Votes and Proceedings document correctly")
	func parsesHappyPathHTML() throws {
		let fixture = try Self.fixture(named: "NS-Votes-2026-03-12", extension: "html")
		let date = try #require(Self.date("2026-03-12T00:00:00Z"))

		let votes = try NovaScotiaVotesParser().parse(document: fixture, sittingDate: date)

		#expect(votes.count == 1)
		let vote = try #require(votes.first)
		#expect(vote.voteID == 6_501_201)
		#expect(vote.number == 12)
		#expect(vote.descriptionEn == "That Bill No. 198, Financial Measures (2026) Act, be now read a second time.")
		#expect(vote.billNumberCode == "198")
		#expect(vote.resultEn == "Carried")
		#expect(vote.yea == 3)
		#expect(vote.nay == 2)
		#expect(vote.paired == 1)
		#expect(vote.jurisdiction == Jurisdiction.novaScotia.rawValue)
		#expect(vote.memberVotes.count == 6)
		#expect(vote.memberVotes.filter { $0.recordedVote == "Yea" }.count == 3)
		#expect(vote.memberVotes.filter { $0.recordedVote == "Nay" }.count == 2)
		#expect(vote.memberVotes.filter { $0.recordedVote == "Abstained" }.count == 1)
	}

	@Test("Parses paired and absent members without failing")
	func parsesPairedAndAbsentMembers() throws {
		let html = """
		<html>
			<body>
				<section data-recorded-vote data-vote-id="6501202" data-result="Carried">
					<p data-motion>That the House do now adjourn.</p>
					<ul data-vote="yeas">
						<li>John White</li>
					</ul>
					<ul data-vote="nays">
						<li>Suzy Hansen</li>
					</ul>
					<ul data-vote="paired">
						<li>Hon. Kim Masland</li>
					</ul>
					<ul data-vote="absent">
						<li>Unnamed Member</li>
					</ul>
				</section>
			</body>
		</html>
		"""
		let votes = try NovaScotiaVotesParser().parse(document: html, sittingDate: Date())

		let vote = try #require(votes.first)
		#expect(vote.yea == 1)
		#expect(vote.nay == 1)
		#expect(vote.paired == 2)
		#expect(vote.memberVotes.contains { $0.recordedVote == "Paired" })
		#expect(vote.memberVotes.contains { $0.recordedVote == "Absent" })
	}

	@Test("Parses older table-style vote blocks")
	func parsesTableStyleVote() throws {
		let html = """
		<html>
			<body>
				<table data-recorded-vote data-vote-number="7" data-result="Negatived">
					<caption>That the amendment to Bill No. 212 be agreed to.</caption>
					<tr><th>Yeas</th><th>Nays</th><th>Paired</th></tr>
					<tr><td>Hon. Brendan Maguire</td><td>Hon. Colton LeBlanc</td><td>Nolan Young</td></tr>
					<tr><td>Lisa Lachance</td><td>Brian Wong</td><td></td></tr>
				</table>
			</body>
		</html>
		"""
		let date = try #require(Self.date("2026-03-13T00:00:00Z"))
		let votes = try NovaScotiaVotesParser().parse(document: html, sittingDate: date)

		let vote = try #require(votes.first)
		#expect(vote.number == 7)
		#expect(vote.descriptionEn == "That the amendment to Bill No. 212 be agreed to.")
		#expect(vote.billNumberCode == "212")
		#expect(vote.resultEn == "Negatived")
		#expect(vote.yea == 2)
		#expect(vote.nay == 2)
		#expect(vote.paired == 1)
	}

	@Test("Ingests NS votes into ModelContext")
	@MainActor
	func ingestsNSVotes() async throws {
		let fixture = try Self.fixture(named: "NS-Votes-2026-03-12", extension: "html")
		let date = try #require(Self.date("2026-03-12T00:00:00Z"))
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try ModelContainer(for: Schema(SchemaV10.models), configurations: config)
		let fetch = Fetch(modelContainer: container)

		try await fetch.ingestNovaScotiaVotes(document: fixture, sittingDate: date)

		let votes = try container.mainContext.fetch(FetchDescriptor<RecordedVote>())
		let memberVotes = try container.mainContext.fetch(FetchDescriptor<MemberVote>())
		#expect(votes.count == 1)
		#expect(memberVotes.count == 6)
		#expect(votes[0].jurisdiction == Jurisdiction.novaScotia.rawValue)
		#expect(memberVotes.allSatisfy { $0.jurisdiction == Jurisdiction.novaScotia.rawValue })
	}

	private static func fixture(named name: String, extension ext: String) throws -> String {
		class ForThisOnly {}
		let url = try #require(Bundle(for: ForThisOnly.self).url(forResource: name, withExtension: ext))
		return try String(contentsOf: url, encoding: .utf8)
	}

	private static func date(_ text: String) -> Date? {
		ISO8601DateFormatter().date(from: text)
	}
}
