//
//  HansardTranscriptTests.swift
//  epacTests
//

@testable import epac
import Foundation
import Testing

struct HansardTranscriptTests {
	private enum Constants {
		static let sittingTimestamp: TimeInterval = 1_800_000_000
		static let secondTimestamp: TimeInterval = 1_800_003_600
		static let parliamentNumber = 45
		static let sessionNumber = 1
		static let expectedSpeechWordCount = 5
		static let sourceURL = URL(string: "https://www.ourcommons.ca/documentviewer/en/45-1/house/hansard?hansardId=45-1-HAN073-E")!
	}

	@Test func identicalTranscriptsAreEqual() {
		let transcript = fixtureTranscript()

		#expect(transcript == fixtureTranscript())
	}

	@Test func jurisdictionCodableRoundTrips() throws {
		let encoded = try JSONEncoder().encode(Jurisdiction.britishColumbia)
		let decoded = try JSONDecoder().decode(Jurisdiction.self, from: encoded)

		#expect(decoded == .britishColumbia)
	}

	@Test func swiftDataMapperPreservesFederalTranscriptRoundTrip() {
		let swiftDataHansard = fixtureSwiftDataHansard()
		let transcript = SwiftDataHansardMapper.transcript(from: swiftDataHansard, sourceURL: Constants.sourceURL)
		let rebuiltHansard = SwiftDataHansardMapper.hansard(
			from: transcript,
			hansardID: swiftDataHansard.hansardID
		)
		let rebuiltTranscript = SwiftDataHansardMapper.transcript(from: rebuiltHansard, sourceURL: Constants.sourceURL)

		#expect(transcript == rebuiltTranscript)
		#expect(transcript.jurisdiction == .federal)
		#expect(transcript.parliamentNumber == Constants.parliamentNumber)
		#expect(transcript.sessionNumber == Constants.sessionNumber)
		#expect(transcript.legislatureNumber == nil)
		#expect(transcript.subjects.first?.speeches.first?.wordCount == Constants.expectedSpeechWordCount)
	}

	private func fixtureTranscript() -> HansardTranscript {
		HansardTranscript(
			jurisdiction: .federal,
			sittingDate: Date(timeIntervalSince1970: Constants.sittingTimestamp),
			parliamentNumber: Constants.parliamentNumber,
			sessionNumber: Constants.sessionNumber,
			legislatureNumber: nil,
			sourceURL: Constants.sourceURL,
			language: Locale(identifier: "en-CA"),
			subjects: [
				SubjectOfBusinessRecord(
					id: "subject-1",
					title: "Housing Affordability",
					speeches: [
						SpeechMessageRecord(
							interventionID: "int-1",
							speakerName: "Mark Carney",
							speakerMemberID: nil,
							text: "We need more homes now.",
							timestamp: Date(timeIntervalSince1970: Constants.secondTimestamp)
						)
					]
				)
			]
		)
	}

	private func fixtureSwiftDataHansard() -> Hansard {
		let date = Date(timeIntervalSince1970: Constants.sittingTimestamp)
		let timestamp = Date(timeIntervalSince1970: Constants.secondTimestamp)
		let message = SpeechMessage(
			firstName: "Mark",
			lastName: "Carney",
			partyAbbreviation: "Lib",
			ridingName: "Nepean",
			hansardID: "int-1",
			content: "We need more homes now.",
			timestamp: timestamp
		)
		let speech = Speech(
			messages: [message],
			hansardID: "speech-1",
			date: date,
			title: "Housing Affordability"
		)
		let subject = SubjectOfBusiness(
			title: "Housing Affordability",
			hansardID: "subject-1",
			speeches: [speech]
		)
		let order = OrderOfBusiness(
			hansardID: "order-1",
			catchline: "Government Orders",
			subjects: [subject]
		)
		return Hansard(
			date: date,
			hansardID: "45-1-HAN073-E",
			parliamentNumber: Constants.parliamentNumber,
			sessionNumber: Constants.sessionNumber,
			orders: [order]
		)
	}
}
