//
//  OntarioVotesParserTests.swift
//  epacTests
//

@testable import epac
import Foundation
import SwiftData
import Testing

@Suite("Ontario Votes Parser Tests")
struct OntarioVotesParserTests {

	@Test("Parses complete HTML Votes and Proceedings document correctly")
	func parsesHappyPathHTML() throws {
		let html = try Self.fixture(named: "ON-Votes-2023-11-16", pathExtension: "html")
		let date = try #require(Self.date("2023-11-16T00:00:00Z"))

		let votes = try OntarioVotesParser().parse(document: html, sittingDate: date)

		#expect(votes.count == 1)
		let vote = try #require(votes.first)
		#expect(vote.parliament == 43)
		#expect(vote.session == 1)
		#expect(vote.descriptionEn == "Second Reading of Bill 146, An Act to implement Budget measures and to enact and amend various statutes.")
		#expect(vote.billNumberCode == "Bill 146")
		#expect(vote.resultEn == "Carried")
		#expect(vote.yea == 95)
		#expect(vote.nay == 0)
		#expect(vote.paired == 0)
		#expect(vote.jurisdiction == Jurisdiction.ontario.rawValue)
		#expect(vote.memberVotes.count == 95)
		#expect(vote.memberVotes.filter { $0.recordedVote == "Aye" }.count == 95)
		#expect(vote.memberVotes.allSatisfy { $0.jurisdiction == Jurisdiction.ontario.rawValue })
	}

	@Test("Parses Paired members as a distinct Ontario vote state")
	func parsesPairedMember() throws {
		let xml = """
		<?xml version="1.0" encoding="utf-8"?>
		<VotesAndProceedings>
			<RecordedVote id="paired-edge">
				<VoteId>2044</VoteId>
				<Parliament>43</Parliament>
				<Session>1</Session>
				<Description>Motion respecting committee membership.</Description>
				<Result>Carried</Result>
				<Ayes>
					<Member>Smith, Jane</Member>
				</Ayes>
				<Paired>
					<Member>Jones, Taylor</Member>
				</Paired>
			</RecordedVote>
		</VotesAndProceedings>
		"""

		let votes = try OntarioVotesParser().parse(document: xml, sittingDate: Date(timeIntervalSince1970: 0))

		let vote = try #require(votes.first)
		#expect(votes.count == 1)
		#expect(vote.yea == 1)
		#expect(vote.paired == 1)
		#expect(vote.memberVotes.filter { $0.recordedVote == "Paired" }.count == 1)
		#expect(vote.memberVotes.contains { $0.recordedVote == "Nay" } == false)
	}

	@Test("Ingests Ontario votes into ModelContext")
	@MainActor
	func ingestsOntarioVotes() async throws {
		let html = try Self.fixture(named: "ON-Votes-2023-11-16", pathExtension: "html")
		let date = try #require(Self.date("2023-11-16T00:00:00Z"))
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try ModelContainer(for: Schema(SchemaV10.models), configurations: config)
		let fetch = Fetch(modelContainer: container)

		try await fetch.ingestOntarioVotes(document: html, sittingDate: date)

		let votes = try container.mainContext.fetch(SwiftData.FetchDescriptor<RecordedVote>())
		let vote = try #require(votes.first)
		#expect(votes.count == 1)
		#expect(vote.jurisdiction == Jurisdiction.ontario.rawValue)
		#expect(vote.memberVotes.count == 95)
	}

	private static func fixture(named name: String, pathExtension: String) throws -> String {
		let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let fixtureURL = testsDirectory
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/Ontario/Votes/\(name).\(pathExtension)")
		return try String(contentsOf: fixtureURL, encoding: .utf8)
	}

	private static func date(_ string: String) -> Date? {
		ISO8601DateFormatter().date(from: string)
	}
}
