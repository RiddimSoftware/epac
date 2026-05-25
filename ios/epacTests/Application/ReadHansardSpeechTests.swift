@testable import epac
import Foundation
import Testing

@MainActor
struct ReadHansardSpeechTests {
	@Test func ordersSpeechesByFirstMessageThenMessagesByHansardID() async throws {
		let date = Self.date(day: 4)
		let targetSubject = SubjectOfBusinessRecord(
			title: "Housing",
			hansardID: "subject-1",
			speeches: [
				Self.speech(id: "speech-b", messageIDs: ["msg-003", "msg-002"], date: date),
				Self.speech(id: "speech-a", messageIDs: ["msg-001"], date: date)
			],
			currentSpeechID: nil
		)
		let transcript = Self.transcript(date: date, subjects: [targetSubject])
		let useCase = ReadHansardSpeech(repository: FixtureHansardRepository(transcripts: [transcript]))

		let messages = try await useCase.execute(
			jurisdiction: .houseOfCommons,
			sittingDate: date,
			subjectID: "subject-1"
		)

		#expect(messages.map(\.hansardID) == ["msg-001", "msg-002", "msg-003"])
		#expect(messages.map(\.speechID) == ["speech-a", "speech-b", "speech-b"])
	}

	@Test func routesJurisdictionToRepository() async throws {
		let date = Self.date(day: 5)
		let jurisdiction = Jurisdiction.provincial(.Ontario)
		let subject = SubjectOfBusinessRecord(
			title: "Question Period",
			hansardID: "subject-on",
			speeches: [Self.speech(id: "speech-on", messageIDs: ["msg-on"], date: date)],
			currentSpeechID: nil
		)
		let transcript = Self.transcript(jurisdiction: jurisdiction, date: date, subjects: [subject])
		let repository = FixtureHansardRepository(transcripts: [transcript])
		let useCase = ReadHansardSpeech(repository: repository)

		_ = try await useCase.execute(
			jurisdiction: jurisdiction,
			sittingDate: date,
			subjectID: "subject-on"
		)

		#expect(repository.fetchRequests.map(\.jurisdiction) == [jurisdiction])
		#expect(repository.fetchRequests.map(\.sittingDate) == [date])
	}

	@Test func missingOrEmptySubjectReturnsNoMessages() async throws {
		let date = Self.date(day: 6)
		let emptySubject = SubjectOfBusinessRecord(
			title: "Routine Proceedings",
			hansardID: "empty-subject",
			speeches: [],
			currentSpeechID: nil
		)
		let transcript = Self.transcript(date: date, subjects: [emptySubject])
		let useCase = ReadHansardSpeech(repository: FixtureHansardRepository(transcripts: [transcript]))

		let emptyMessages = try await useCase.execute(
			jurisdiction: .houseOfCommons,
			sittingDate: date,
			subjectID: "empty-subject"
		)
		let missingMessages = try await useCase.execute(
			jurisdiction: .houseOfCommons,
			sittingDate: date,
			subjectID: "missing"
		)

		#expect(emptyMessages.isEmpty)
		#expect(missingMessages.isEmpty)
	}

	private static func transcript(
		jurisdiction: Jurisdiction = .houseOfCommons,
		date: Date,
		subjects: [SubjectOfBusinessRecord]
	) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: date,
			hansardID: "h-\(Int(date.timeIntervalSince1970))",
			parliamentNumber: nil,
			sessionNumber: nil,
			orders: [
				OrderOfBusinessRecord(
					hansardID: "order-1",
					catchline: "Debates",
					subjects: subjects
				)
			]
		)
	}

	private static func speech(id: String, messageIDs: [String], date: Date) -> HansardSpeechRecord {
		HansardSpeechRecord(
			messages: messageIDs.map {
				SpeechMessageRecord(
					speechID: id,
					firstName: "A",
					lastName: "Member",
					partyAbbreviation: "Lib",
					ridingName: "Riding",
					hansardID: $0,
					content: $0,
					timestamp: date
				)
			},
			hansardID: id,
			currentMessageID: nil,
			date: date,
			length: messageIDs.count,
			title: id
		)
	}

	private static func date(day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
	}
}
