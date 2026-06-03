//
//  MinisterialExpensesService.swift
//  epac
//

import Foundation

// Decodes the bundled ministerial-expenses.json snapshot. Ministerial travel
// and hospitality disclosures are published quarterly per-department under the
// TBS Proactive Disclosure Directive. The Python ingestion script
// (backend/expenses/ministerial_ingest.py) regenerates this file and the
// result is bundled with the app release. The data is re-seeded on every app
// launch so field format changes are absorbed without a migration.
struct MinisterialExpensesSnapshot: Decodable {
    struct Record: Decodable {
        let recordID: String
        let ministerName: String
        let department: String
        let eventPurpose: String
        let destination: String
        let startDate: String
        let endDate: String?
        let travelCost: Double
        let hospitalityCost: Double
        let totalCost: Double
        let fiscalYear: String
        let quarter: Int
        let sourceURL: String
    }

    let version: Int
    let lastUpdated: String
    let records: [Record]
}

enum MinisterialExpensesServiceError: Error {
    case bundleResourceMissing
    case decodeFailed(Error)
}

struct MinisterialExpensesService {
    static let bundleResourceName = "ministerial-expenses"

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadSnapshot() throws -> MinisterialExpensesSnapshot {
        guard let url = bundle.url(forResource: Self.bundleResourceName, withExtension: "json") else {
            throw MinisterialExpensesServiceError.bundleResourceMissing
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(MinisterialExpensesSnapshot.self, from: data)
        } catch {
            throw MinisterialExpensesServiceError.decodeFailed(error)
        }
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)
    }
}
