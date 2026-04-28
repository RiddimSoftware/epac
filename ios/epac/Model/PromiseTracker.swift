//
//  PromiseTracker.swift
//  epac
//
//  Created on 2026-04-28.
//

import Foundation

struct PromiseTrackerDataset: Decodable, Equatable {
	let metadata: PromiseTrackerMetadata
	let commitments: [PromiseCommitment]
}

struct PromiseTrackerMetadata: Decodable, Equatable {
	let title: String
	let governingParty: String
	let governmentLeader: String
	let platformTitle: String
	let platformUrl: String
	let governmentVerificationUrl: String
	let lastReviewed: String
	let reviewPolicy: String
	let curationNote: String
}

struct PromiseCommitment: Decodable, Equatable, Identifiable {
	let id: String
	let category: String
	let promise: String
	let source: PromiseSource
	let status: PromiseTrackerStatus
	let statusRationale: String
	let evidence: [PromiseEvidence]
}

struct PromiseSource: Decodable, Equatable {
	let title: String
	let url: String
	let location: String
}

struct PromiseEvidence: Decodable, Equatable, Identifiable {
	var id: String { "\(type)|\(title)|\(url)" }

	let type: String
	let title: String
	let url: String
	let citation: String
}

enum PromiseTrackerStatus: String, CaseIterable, Codable, Equatable {
	case kept = "Kept"
	case partiallyKept = "Partially Kept"
	case notStarted = "Not Started"
	case broken = "Broken"
	case inProgress = "In Progress"

	var tone: PromiseTrackerStatusTone {
		switch self {
		case .kept:
			return .green
		case .inProgress, .partiallyKept:
			return .amber
		case .notStarted, .broken:
			return .red
		}
	}
}

enum PromiseTrackerStatusTone: Equatable {
	case green
	case amber
	case red
}

enum PromiseTrackerRepository {
	enum LoadError: LocalizedError, Equatable {
		case missingResource

		var errorDescription: String? {
			switch self {
			case .missingResource:
				return "promise-tracker.json was not found in the app bundle."
			}
		}
	}

	static func load(bundle: Bundle = .main) throws -> PromiseTrackerDataset {
		guard let url = bundle.url(forResource: "promise-tracker", withExtension: "json")
				?? bundle.url(forResource: "promise-tracker", withExtension: "json", subdirectory: "data") else {
			throw LoadError.missingResource
		}
		let data = try Data(contentsOf: url)
		return try decode(data)
	}

	static func decode(_ data: Data) throws -> PromiseTrackerDataset {
		try JSONDecoder().decode(PromiseTrackerDataset.self, from: data)
	}
}
