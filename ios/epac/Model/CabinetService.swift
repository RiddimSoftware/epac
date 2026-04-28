//
//  CabinetService.swift
//  epac
//

import Foundation

// Decodes the bundled cabinet-positions.json snapshot. The JSON is the canonical
// source for who currently sits in Cabinet — keeping it as a bundled resource
// means the feature works offline on first launch. The Python ingestion script
// (backend/cabinet/cabinet_ingest.py) regenerates this file from pm.gc.ca.
struct CabinetSnapshot: Decodable {
	struct Source: Decodable {
		let title: String
		let url: String
	}
	struct MandateLettersIndex: Decodable {
		let url: String
		let available: Bool
		let note: String?
	}
	struct Position: Decodable {
		let ministerName: String
		let firstName: String
		let lastName: String
		let portfolio: String
		let isPrimeMinister: Bool?
		let mandateLetterURL: String?
	}

	let version: Int
	let asOfDate: String
	let source: Source
	let mandateLettersIndex: MandateLettersIndex?
	let positions: [Position]
}

enum CabinetServiceError: Error {
	case bundleResourceMissing
	case decodeFailed(Error)
	case invalidAsOfDate(String)
}

struct CabinetService {
	static let bundleResourceName = "cabinet-positions"

	private let bundle: Bundle

	init(bundle: Bundle = .main) {
		self.bundle = bundle
	}

	func loadSnapshot() throws -> CabinetSnapshot {
		guard let url = bundle.url(forResource: Self.bundleResourceName, withExtension: "json") else {
			throw CabinetServiceError.bundleResourceMissing
		}
		let data = try Data(contentsOf: url)
		do {
			return try JSONDecoder().decode(CabinetSnapshot.self, from: data)
		} catch {
			throw CabinetServiceError.decodeFailed(error)
		}
	}

	static func parseAsOfDate(_ string: String) throws -> Date {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withFullDate]
		if let date = formatter.date(from: string) { return date }
		throw CabinetServiceError.invalidAsOfDate(string)
	}
}
