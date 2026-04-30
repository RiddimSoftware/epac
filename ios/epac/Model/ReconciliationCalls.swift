//
//  ReconciliationCalls.swift
//  epac
//
//  Created on 2026-04-28.
//

import Foundation

struct ReconciliationCallsDataset: Decodable, Equatable {
	let metadata: ReconciliationMetadata
	let calls: [ReconciliationCall]
}

struct ReconciliationMetadata: Decodable, Equatable {
	let title: String
	let lastReviewed: String
	let yellowheadReportYear: Int
	let yellowheadReportUrl: String
	let yellowheadUpdateUrl: String
	let cbcBeyond94Url: String
	let trcPublicationUrl: String
	let trcPdfUrl: String
	let curationNote: String
}

struct ReconciliationCall: Decodable, Equatable, Identifiable {
	let id: String
	let number: Int
	let theme: ReconciliationTheme
	let title: String
	let callText: String
	let responsibleParty: String
	let status: ReconciliationStatus
	let implementationPhase: String
	let yellowheadStatus: String
	let statusSummary: String
	let lastReviewed: String
	let statusAttribution: String
	let trcSource: ReconciliationSource
	let statusSource: ReconciliationStatusSource
	let primarySource: ReconciliationSource
	let statusHistory: [ReconciliationStatusHistory]
}

enum ReconciliationTheme: String, CaseIterable, Codable, Equatable, Identifiable {
	case childWelfare = "Child Welfare"
	case education = "Education"
	case languageAndCulture = "Language and Culture"
	case health = "Health"
	case justice = "Justice"
	case reconciliation = "Reconciliation"

	var id: String { rawValue }
}

enum ReconciliationStatus: String, CaseIterable, Codable, Equatable {
	case notStarted = "Not Started"
	case inProgress = "In Progress"
	case completed = "Completed"

	var tone: ReconciliationStatusTone {
		switch self {
		case .completed:
			return .green
		case .inProgress:
			return .amber
		case .notStarted:
			return .red
		}
	}
}

enum ReconciliationStatusTone: Equatable {
	case green
	case amber
	case red
}

struct ReconciliationSource: Decodable, Equatable {
	let title: String
	let url: String
	let pdfUrl: String?

	init(title: String, url: String, pdfUrl: String? = nil) {
		self.title = title
		self.url = url
		self.pdfUrl = pdfUrl
	}
}

struct ReconciliationStatusSource: Decodable, Equatable {
	let title: String
	let url: String
	let lastUpdated: String
}

struct ReconciliationStatusHistory: Decodable, Equatable, Identifiable {
	var id: String { "\(year)|\(status)|\(source)" }

	let year: Int
	let status: String
	let source: String
	let url: String
}

enum ReconciliationCallsRepository {
	enum LoadError: LocalizedError, Equatable {
		case missingResource

		var errorDescription: String? {
			switch self {
			case .missingResource:
				return "reconciliation-calls.json was not found in the app bundle."
			}
		}
	}

	static func load(bundle: Bundle = .main) throws -> ReconciliationCallsDataset {
		guard let url = bundle.url(forResource: "reconciliation-calls", withExtension: "json")
				?? bundle.url(forResource: "reconciliation-calls", withExtension: "json", subdirectory: "data") else {
			throw LoadError.missingResource
		}
		let data = try Data(contentsOf: url)
		return try decode(data)
	}

	static func decode(_ data: Data) throws -> ReconciliationCallsDataset {
		try JSONDecoder().decode(ReconciliationCallsDataset.self, from: data)
	}
}
