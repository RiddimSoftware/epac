//
//  SwiftDataHansardRepository.swift
//  epac
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataHansardRepository: HansardRepository, @unchecked Sendable {
	private let modelContext: ModelContext
	private let fetch: Fetch

	init(modelContext: ModelContext, fetch: Fetch) {
		self.modelContext = modelContext
		self.fetch = fetch
	}

	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		try requireSupported(jurisdiction)

		if let cached = try cachedHansard(on: sittingDate) {
			return cached.transcript(jurisdiction: jurisdiction)
		}

		try await fetch.downloadHansard(sittingDate)
		guard let fetched = try cachedHansard(on: sittingDate) else {
			throw SwiftDataHansardRepositoryError.transcriptNotFound(jurisdiction: jurisdiction, sittingDate: sittingDate)
		}
		return fetched.transcript(jurisdiction: jurisdiction)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> [Date] {
		try requireSupported(jurisdiction)
		guard from <= to else { return [] }

		var dates: [Date] = []
		for year in years(from: from, to: to) {
			let descriptor = FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })
			var calendar = try modelContext.fetch(descriptor).first
			if calendar == nil {
				try await fetch.downloadSittingCalendar(year)
				calendar = try modelContext.fetch(descriptor).first
			}
			if let calendar {
				dates.append(contentsOf: calendar.sittings)
			}
		}

		return dates
			.filter { from <= $0 && $0 <= to }
			.removingDuplicates()
			.sorted()
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		try requireSupported(transcript.jurisdiction)

		let existing = try modelContext.fetch(FetchDescriptor<Hansard>(
			predicate: #Predicate { $0.date == transcript.sittingDate }
		))
		if existing.count == 1, existing.first?.transcript(jurisdiction: transcript.jurisdiction) == transcript {
			return
		}
		for hansard in existing {
			deleteHansardAggregate(hansard)
		}
		modelContext.insert(Hansard(transcript: transcript))
		try modelContext.save()
	}

	private func cachedHansard(on sittingDate: Date) throws -> Hansard? {
		try modelContext.fetch(FetchDescriptor<Hansard>(
			predicate: #Predicate { $0.date == sittingDate }
		)).first
	}

	private func requireSupported(_ jurisdiction: Jurisdiction) throws {
		guard jurisdiction == .houseOfCommons else {
			throw SwiftDataHansardRepositoryError.unsupportedJurisdiction(jurisdiction)
		}
	}

	private func years(from start: Date, to end: Date) -> [Int] {
		let calendar = Calendar.current
		guard let startYear = calendar.dateComponents([.year], from: start).year,
		      let endYear = calendar.dateComponents([.year], from: end).year else {
			return []
		}
		return Array(startYear...endYear)
	}

	private func deleteHansardAggregate(_ hansard: Hansard) {
		for order in hansard.orders {
			for subject in order.subjects {
				for speech in subject.speeches {
					for message in speech.messages {
						modelContext.delete(message)
					}
					modelContext.delete(speech)
				}
				modelContext.delete(subject)
			}
			modelContext.delete(order)
		}
		modelContext.delete(hansard)
	}
}

enum SwiftDataHansardRepositoryError: Error, Equatable {
	case unsupportedJurisdiction(Jurisdiction)
	case transcriptNotFound(jurisdiction: Jurisdiction, sittingDate: Date)
}

extension Hansard {
	convenience init(transcript: HansardTranscript) {
		self.init(
			date: transcript.sittingDate,
			hansardID: transcript.hansardID,
			parliamentNumber: transcript.parliamentNumber ?? 0,
			sessionNumber: transcript.sessionNumber ?? 0,
			orders: transcript.orders.map(OrderOfBusiness.init(record:))
		)
	}

	func transcript(jurisdiction: Jurisdiction) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: date,
			hansardID: hansardID,
			parliamentNumber: parliamentNumber,
			sessionNumber: sessionNumber,
			orders: orders.map(\.record)
		)
	}
}

extension OrderOfBusiness {
	convenience init(record: OrderOfBusinessRecord) {
		self.init(
			hansardID: record.hansardID,
			catchline: record.catchline,
			subjects: record.subjects.map(SubjectOfBusiness.init(record:))
		)
	}

	var record: OrderOfBusinessRecord {
		OrderOfBusinessRecord(
			hansardID: hansardID,
			catchline: catchline,
			subjects: subjects.map(\.record)
		)
	}
}

extension SubjectOfBusiness {
	convenience init(record: SubjectOfBusinessRecord) {
		let speeches = record.speeches.map(Speech.init(record:))
		self.init(title: record.title, hansardID: record.hansardID, speeches: speeches)
		currentSpeechID = record.currentSpeechID
		currentSpeech = speeches.first { $0.hansardID == record.currentSpeechID }
	}

	var record: SubjectOfBusinessRecord {
		SubjectOfBusinessRecord(
			title: title,
			hansardID: hansardID,
			speeches: speeches.map(\.record),
			currentSpeechID: currentSpeechID ?? currentSpeech?.hansardID
		)
	}
}

extension Speech {
	convenience init(record: HansardSpeechRecord) {
		let messages = record.messages.map(SpeechMessage.init(record:))
		self.init(messages: messages, hansardID: record.hansardID, date: record.date, title: record.title)
		currentMessageID = record.currentMessageID
		currentMessage = messages.first { $0.hansardID == record.currentMessageID }
		length = record.length
	}

	var record: HansardSpeechRecord {
		HansardSpeechRecord(
			messages: messages.map { $0.record(speechID: hansardID) },
			hansardID: hansardID,
			currentMessageID: currentMessageID ?? currentMessage?.hansardID,
			date: date,
			length: length,
			title: title
		)
	}
}

extension SpeechMessage {
	convenience init(record: SpeechMessageRecord) {
		self.init(
			firstName: record.firstName,
			lastName: record.lastName,
			partyAbbreviation: record.partyAbbreviation,
			ridingName: record.ridingName,
			hansardID: record.hansardID,
			content: record.content,
			timestamp: record.timestamp
		)
	}

	func record(speechID: String) -> SpeechMessageRecord {
		SpeechMessageRecord(
			speechID: speechID,
			firstName: firstName,
			lastName: lastName,
			partyAbbreviation: partyAbbreviation,
			ridingName: ridingName,
			hansardID: hansardID,
			content: content,
			timestamp: timestamp
		)
	}
}

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
