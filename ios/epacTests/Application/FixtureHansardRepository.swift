@testable import epac
import Foundation

@MainActor
final class FixtureHansardRepository: HansardRepository {
	private var transcripts: [Key: HansardTranscript]
	var sittingDates: [Date]
	var fetchError: Error?
	var listError: Error?
	var storeError: Error?
	private(set) var fetchRequests: [(jurisdiction: Jurisdiction, sittingDate: Date)] = []
	private(set) var listRequests: [(jurisdiction: Jurisdiction, from: Date, to: Date)] = []
	private(set) var storedTranscripts: [HansardTranscript] = []

	init(transcripts: [HansardTranscript] = [], sittingDates: [Date] = []) {
		self.transcripts = Dictionary(uniqueKeysWithValues: transcripts.map {
			(Key(jurisdiction: $0.jurisdiction, sittingDate: $0.sittingDate), $0)
		})
		self.sittingDates = sittingDates
	}

	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		fetchRequests.append((jurisdiction, sittingDate))
		if let fetchError {
			throw fetchError
		}
		guard let transcript = transcripts[Key(jurisdiction: jurisdiction, sittingDate: sittingDate)] else {
			throw FixtureHansardRepositoryError.missingTranscript
		}
		return transcript
	}

	func listSittingDates(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> [Date] {
		listRequests.append((jurisdiction, from, to))
		if let listError {
			throw listError
		}
		return sittingDates
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		if let storeError {
			throw storeError
		}
		storedTranscripts.append(transcript)
		transcripts[Key(jurisdiction: transcript.jurisdiction, sittingDate: transcript.sittingDate)] = transcript
	}
}

enum FixtureHansardRepositoryError: Error, Equatable {
	case fetchFailed
	case listFailed
	case storeFailed
	case missingTranscript
}

private struct Key: Hashable {
	let jurisdiction: Jurisdiction
	let sittingDate: Date
}
