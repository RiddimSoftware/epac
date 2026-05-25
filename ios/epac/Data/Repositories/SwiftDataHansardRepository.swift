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
			return SwiftDataHansardMapper.transcript(from: cached)
		}

		try await fetch.downloadHansard(sittingDate)
		guard let fetched = try cachedHansard(on: sittingDate) else {
			throw SwiftDataHansardRepositoryError.transcriptNotFound(jurisdiction: jurisdiction, sittingDate: sittingDate)
		}
		return SwiftDataHansardMapper.transcript(from: fetched)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
		try requireSupported(jurisdiction)
		guard startDate <= endDate else { return [] }

		var dates: [Date] = []
		for year in years(from: startDate, through: endDate) {
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
			.filter { startDate <= $0 && $0 <= endDate }
			.removingDuplicates()
			.sorted()
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		try requireSupported(transcript.jurisdiction)

		let sittingDate = transcript.sittingDate
		let existing = try modelContext.fetch(FetchDescriptor<Hansard>(
			predicate: #Predicate { $0.date == sittingDate }
		))
		if existing.count == 1, existing.first.map({ SwiftDataHansardMapper.transcript(from: $0) }) == transcript {
			return
		}
		for hansard in existing {
			deleteHansardAggregate(hansard)
		}
		modelContext.insert(SwiftDataHansardMapper.hansard(from: transcript))
		try modelContext.save()
	}

	private func cachedHansard(on sittingDate: Date) throws -> Hansard? {
		try modelContext.fetch(FetchDescriptor<Hansard>(
			predicate: #Predicate { $0.date == sittingDate }
		)).first
	}

	private func requireSupported(_ jurisdiction: Jurisdiction) throws {
		guard jurisdiction == .federal else {
			throw SwiftDataHansardRepositoryError.unsupportedJurisdiction(jurisdiction)
		}
	}

	private func years(from start: Date, through end: Date) -> [Int] {
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

private extension Array where Element: Hashable {
	func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
