//
//  EmploymentInsuranceStatistics.swift
//  epac
//

import Foundation

struct EmploymentInsuranceMonth: Decodable, Identifiable {
    var id: String { refDate }

    let refDate: String
    let beneficiaries: Int
    let claimsReceived: Int
    let averageWeeklyBenefit: Double

    enum CodingKeys: String, CodingKey {
        case refDate = "ref_date"
        case beneficiaries
        case claimsReceived = "claims_received"
        case averageWeeklyBenefit = "average_weekly_benefit"
    }
}

struct EmploymentInsuranceStatistic: Decodable, Identifiable {
    var id: String { provinceCode }

    let province: String
    let provinceCode: String
    let referenceMonth: String
    let beneficiaries: Int
    let claimsReceived: Int
    let claimsReceivedPreviousYear: Int?
    let claimsYearOverYearChangePercent: Double?
    let averageWeeklyBenefit: Double
    let months: [EmploymentInsuranceMonth]

    enum CodingKeys: String, CodingKey {
        case province
        case provinceCode = "province_code"
        case referenceMonth = "reference_month"
        case beneficiaries
        case claimsReceived = "claims_received"
        case claimsReceivedPreviousYear = "claims_received_previous_year"
        case claimsYearOverYearChangePercent = "claims_year_over_year_change_percent"
        case averageWeeklyBenefit = "average_weekly_benefit"
        case months
    }
}

struct EmploymentInsuranceSource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct EmploymentInsuranceSnapshot: Decodable {
    let referenceMonth: String
    let source: EmploymentInsuranceSource
    let provinces: [EmploymentInsuranceStatistic]

    enum CodingKeys: String, CodingKey {
        case referenceMonth = "reference_month"
        case source
        case provinces
    }
}

enum EmploymentInsuranceStatisticsDatabase {
    private static let resourceName = "ei-statistics"
    private static let mainSnapshot = loadSnapshot(bundle: .main)
    private enum DateParsing {
        static let componentCount = 2
        static let validMonthRange = 1...12
        static let monthSymbolIndexOffset = 1
    }

    static let fallbackSource = EmploymentInsuranceSource(
        title: "Employment and Social Development Canada — EI Statistics",
        url: URL(string: "https://www.canada.ca/en/employment-social-development/programs/ei/statistics.html")!,
        note: "Monthly Statistics Canada EI tables are produced from Service Canada and ESDC administrative data."
    )

    static func snapshot(bundle: Bundle = .main) -> EmploymentInsuranceSnapshot? {
        if bundle === Bundle.main {
            return mainSnapshot
        }
        return loadSnapshot(bundle: bundle)
    }

    private static func loadSnapshot(bundle: Bundle) -> EmploymentInsuranceSnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }

    static func statistic(for provinceCode: String, bundle: Bundle = .main) -> EmploymentInsuranceStatistic? {
        snapshot(bundle: bundle)?
            .provinces
            .first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame }
    }

    static func decode(data: Data) throws -> EmploymentInsuranceSnapshot {
        try JSONDecoder().decode(EmploymentInsuranceSnapshot.self, from: data)
    }

    static func monthLabel(_ refDate: String) -> String {
        let parts = refDate.split(separator: "-")
        guard parts.count == DateParsing.componentCount,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              DateParsing.validMonthRange.contains(month) else {
            return refDate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        let monthName = formatter.monthSymbols[month - DateParsing.monthSymbolIndexOffset]
        return "\(monthName) \(year)"
    }
}
