@testable import epac
import Foundation
import Testing

@MainActor
struct ReadHansardSpeechTests {
	@Test func ordersSpeechesByFirstMessageThenMessagesByHansardID() async throws {
		let date = Self.date(day: 4)
		let targetSubject = SubjectOfBusinessRecord(
			id: "subject-1",
			title: "Housing",
			speeches: Self.messages(ids: ["msg-003", "msg-002", "msg-001"], date: date)
		)
		let transcript = Self.transcript(date: date, subjects: [targetSubject])
		let useCase = ReadHansardSpeech(repository: FixtureHansardRepository(transcripts: [transcript]))

		let messages = try await useCase.execute(
			jurisdiction: .federal,
			sittingDate: date,
			subjectID: "subject-1"
		)

		#expect(messages.map(\.interventionID) == ["msg-001", "msg-002", "msg-003"])
	}

	@Test func routesJurisdictionToRepository() async throws {
		let date = Self.date(day: 5)
		let jurisdiction = Jurisdiction.ontario
		let subject = SubjectOfBusinessRecord(
			id: "subject-on",
			title: "Question Period",
			speeches: Self.messages(ids: ["msg-on"], date: date)
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
			id: "empty-subject",
			title: "Routine Proceedings",
			speeches: []
		)
		let transcript = Self.transcript(date: date, subjects: [emptySubject])
		let useCase = ReadHansardSpeech(repository: FixtureHansardRepository(transcripts: [transcript]))

		let emptyMessages = try await useCase.execute(
			jurisdiction: .federal,
			sittingDate: date,
			subjectID: "empty-subject"
		)
		let missingMessages = try await useCase.execute(
			jurisdiction: .federal,
			sittingDate: date,
			subjectID: "missing"
		)

		#expect(emptyMessages.isEmpty)
		#expect(missingMessages.isEmpty)
	}

	private static func transcript(
		jurisdiction: Jurisdiction = .federal,
		date: Date,
		subjects: [SubjectOfBusinessRecord]
	) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: date,
			parliamentNumber: nil,
			sessionNumber: nil,
			legislatureNumber: nil,
			sourceURL: Self.sourceURL(for: date),
			language: Locale(identifier: "en-CA"),
			subjects: subjects
		)
	}

	private static func messages(ids: [String], date: Date) -> [SpeechMessageRecord] {
		ids.map {
			SpeechMessageRecord(
				interventionID: $0,
				speakerName: "A Member",
				speakerMemberID: nil,
				text: $0,
				timestamp: date
			)
		}
	}

	private static func date(day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
	}

	private static func sourceURL(for date: Date) -> URL {
		URL(string: "https://example.com/hansard/\(Int(date.timeIntervalSince1970))")!
	}
}
