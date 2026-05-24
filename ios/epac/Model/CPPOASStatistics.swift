//
//  CPPOASStatistics.swift
//  epac
//

import Foundation

struct CPPOASYear: Decodable, Identifiable {
    var id: Int { year }

    let year: Int
    let cppRetirementRecipients: Int?
    let oasPensionRecipients: Int?

    enum CodingKeys: String, CodingKey {
        case year
        case cppRetirementRecipients = "cpp_retirement_recipients"
        case oasPensionRecipients = "oas_pension_recipients"
    }
}

struct CPPOASStatistic: Decodable, Identifiable {
    var id: String { provinceCode }

    let province: String
    let provinceCode: String
    let cppRetirementRecipients: Int?
    let cppReferencePeriod: String?
    let oasPensionRecipients: Int?
    let oasReferencePeriod: String?
    let history: [CPPOASYear]

    enum CodingKeys: String, CodingKey {
        case province
        case provinceCode = "province_code"
        case cppRetirementRecipients = "cpp_retirement_recipients"
        case cppReferencePeriod = "cpp_reference_period"
        case oasPensionRecipients = "oas_pension_recipients"
        case oasReferencePeriod = "oas_reference_period"
        case history
    }
}

struct CPPOASNational: Decodable {
    let cppRetirementRecipients: Int
    let cppReferencePeriod: String
    let oasPensionRecipients: Int
    let oasReferencePeriod: String

    enum CodingKeys: String, CodingKey {
        case cppRetirementRecipients = "cpp_retirement_recipients"
        case cppReferencePeriod = "cpp_reference_period"
        case oasPensionRecipients = "oas_pension_recipients"
        case oasReferencePeriod = "oas_reference_period"
    }
}

struct CPPOASSource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct CPPOASSnapshot: Decodable {
    let historyYears: [Int]
    let source: CPPOASSource
    let provinces: [CPPOASStatistic]
    let national: CPPOASNational

    enum CodingKeys: String, CodingKey {
        case historyYears = "history_years"
        case source
        case provinces
        case national
    }
}

enum CPPOASStatisticsDatabase {
    private static let resourceName = "cpp-oas-statistics"
    private static let mainSnapshot = loadSnapshot(bundle: .main)

    static let fallbackSource = CPPOASSource(
        title: "Employment and Social Development Canada — CPP/OAS Statistical Bulletin",
        url: URL(string: "https://www.canada.ca/en/employment-social-development/programs/pensions/reports/statistical-bulletin.html")!,
        note: "Provincial recipient counts are published monthly by ESDC on open.canada.ca."
    )

    static func snapshot(bundle: Bundle = .main) -> CPPOASSnapshot? {
        if bundle === Bundle.main {
            return mainSnapshot
        }
        return loadSnapshot(bundle: bundle)
    }

    private static func loadSnapshot(bundle: Bundle) -> CPPOASSnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }

    static func statistic(for provinceCode: String, bundle: Bundle = .main) -> CPPOASStatistic? {
        snapshot(bundle: bundle)?
            .provinces
            .first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame }
    }

    static func national(bundle: Bundle = .main) -> CPPOASNational? {
        snapshot(bundle: bundle)?.national
    }

    static func decode(data: Data) throws -> CPPOASSnapshot {
        try JSONDecoder().decode(CPPOASSnapshot.self, from: data)
    }

    // "2026-04" → "April 2026"
    static func periodLabel(_ refPeriod: String) -> String {
        let parts = refPeriod.split(separator: "-")
        // swiftlint:disable:next no_magic_numbers
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              // swiftlint:disable:next no_magic_numbers
              (1...12).contains(month) else {
            return refPeriod
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        let monthName = formatter.monthSymbols[month - 1]
        return "\(monthName) \(year)"
    }
}
