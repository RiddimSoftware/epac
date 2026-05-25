//
//  SaskatchewanVotesParserTests.swift
//  epacTests
//

import Testing
import Foundation
import SwiftData
@testable import epac

@Suite("Saskatchewan Votes Parser Tests")
struct SaskatchewanVotesParserTests {

	@Test("Parses complete XML Votes and Proceedings document correctly")
	func parsesHappyPathXML() throws {
		class ForThisOnly {}
		let fixtureURL = Bundle(for: ForThisOnly.self).url(forResource: "SK-Votes-2023-03-01", withExtension: "xml")!
		let xmlString = try String(contentsOf: fixtureURL, encoding: .utf8)

		let date = ISO8601DateFormatter().date(from: "2023-03-01T00:00:00Z")!

		let parser = SaskatchewanVotesParser()
		let votes = try parser.parse(document: xmlString, sittingDate: date)

		#expect(votes.count == 1)

		let vote = votes[0]
		#expect(vote.voteID == 101)
		#expect(vote.descriptionEn == "Motion to amend Bill 12 - That the bill be amended as follows")
		#expect(vote.resultEn == "Negatived")
		#expect(vote.yea == 2)
		#expect(vote.nay == 3)
		#expect(vote.paired == 1)
		#expect(vote.jurisdiction == Jurisdiction.saskatchewan.rawValue)

		#expect(vote.memberVotes.count == 6)

		let yeas = vote.memberVotes.filter { $0.recordedVote == "Yea" }
		#expect(yeas.count == 2)

		let paired = vote.memberVotes.filter { $0.recordedVote == "Paired" }
		#expect(paired.count == 1)
	}

	@Test("Parses Paired or Abstaining members correctly")
	func parsesEdgeCasePairedMember() throws {
		let xmlString = """
		<?xml version="1.0" encoding="utf-8"?>
		<VotesAndProceedings>
			<RecordedVotes>
				<Vote>
					<VoteId>102</VoteId>
					<Result>Passed</Result>
					<Paired>
						<Member>Smith, John</Member>
					</Paired>
					<Abstained>
						<Member>Doe, Jane</Member>
					</Abstained>
				</Vote>
			</RecordedVotes>
		</VotesAndProceedings>
		"""
		let parser = SaskatchewanVotesParser()
		let date = Date()
		let votes = try parser.parse(document: xmlString, sittingDate: date)

		#expect(votes.count == 1)
		let vote = votes[0]

		// In our delegate, both Paired and Abstained set currentVoteType = "Paired"
		#expect(vote.paired == 2)
		#expect(vote.memberVotes.filter { $0.recordedVote == "Paired" }.count == 2)
	}

	@Test("Ingests SK votes into ModelContext")
	@MainActor
	func ingestsSKVotes() async throws {
		class ForThisOnly {}
		let fixtureURL = Bundle(for: ForThisOnly.self).url(forResource: "SK-Votes-2023-03-01", withExtension: "xml")!
		let xmlString = try String(contentsOf: fixtureURL, encoding: .utf8)
		let date = ISO8601DateFormatter().date(from: "2023-03-01T00:00:00Z")!

		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try ModelContainer(for: Schema(SchemaV10.models), configurations: config)
		let fetch = Fetch(modelContainer: container)

		try await fetch.ingestSaskatchewanVotes(document: xmlString, sittingDate: date)

		let votes = try container.mainContext.fetch(SwiftData.FetchDescriptor<RecordedVote>())
		#expect(votes.count == 1)
		#expect(votes[0].voteID == 101)
		#expect(votes[0].jurisdiction == Jurisdiction.saskatchewan.rawValue)
	}
}
