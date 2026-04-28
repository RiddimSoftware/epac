//
//  StudentFinancialAssistanceStatistics.swift
//  epac
//

import Foundation

struct StudentFinanceTuitionYear: Decodable, Identifiable {
    var id: String { academicYear }

    let academicYear: String
    let averageUndergraduateTuition: Int
    let yearOverYearChangePercent: Double?

    enum CodingKeys: String, CodingKey {
        case academicYear = "academic_year"
        case averageUndergraduateTuition = "average_undergraduate_tuition"
        case yearOverYearChangePercent = "year_over_year_change_percent"
    }
}

struct StudentFinanceCSFAYear: Decodable, Identifiable {
    var id: String { academicYear }

    let academicYear: String
    let loanRecipients: Int
    let loanDisbursementsMillions: Double
    let averageLoanAmount: Int
    let rapRecipients: Int?

    enum CodingKeys: String, CodingKey {
        case academicYear = "academic_year"
        case loanRecipients = "loan_recipients"
        case loanDisbursementsMillions = "loan_disbursements_millions"
        case averageLoanAmount = "average_loan_amount"
        case rapRecipients = "rap_recipients"
    }
}

struct StudentFinanceNationalRAPYear: Decodable, Identifiable {
    var id: String { academicYear }

    let academicYear: String
    let rapRecipients: Int

    enum CodingKeys: String, CodingKey {
        case academicYear = "academic_year"
        case rapRecipients = "rap_recipients"
    }
}

struct StudentFinanceProvinceStatistic: Decodable, Identifiable {
    var id: String { provinceCode }

    let province: String
    let provinceCode: String
    let csfaParticipating: Bool
    let tuitionYears: [StudentFinanceTuitionYear]
    let csfaYears: [StudentFinanceCSFAYear]

    var latestTuitionYear: StudentFinanceTuitionYear? { tuitionYears.last }
    var latestCSFAYear: StudentFinanceCSFAYear? { csfaYears.last }

    enum CodingKeys: String, CodingKey {
        case province
        case provinceCode = "province_code"
        case csfaParticipating = "csfa_participating"
        case tuitionYears = "tuition_years"
        case csfaYears = "csfa_years"
    }
}

struct StudentFinanceSource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct StudentFinanceSnapshot: Decodable {
    let referenceAcademicYear: String
    let tuitionReferenceYear: String
    let source: StudentFinanceSource
    let sources: [StudentFinanceSource]
    let nationalRAPRecipients: [StudentFinanceNationalRAPYear]
    let provinces: [StudentFinanceProvinceStatistic]

    enum CodingKeys: String, CodingKey {
        case referenceAcademicYear = "reference_academic_year"
        case tuitionReferenceYear = "tuition_reference_year"
        case source
        case sources
        case nationalRAPRecipients = "national_rap_recipients"
        case provinces
    }
}

enum StudentFinancialAssistanceStatisticsDatabase {
    private static let resourceName = "student-finance-statistics"
    private static let mainSnapshot = loadSnapshot(bundle: .main)

    static let fallbackSource = StudentFinanceSource(
        title: "ESDC CSFA Program and Statistics Canada tuition data",
        url: URL(string: "https://www.canada.ca/en/employment-social-development/programs/canada-student-loans-grants/reports/student-financial-assistance-statistics-2023-2024.html")!,
        note: "Federal student assistance and tuition data are published annually."
    )

    static func snapshot(bundle: Bundle = .main) -> StudentFinanceSnapshot? {
        if bundle === Bundle.main {
            return mainSnapshot
        }
        return loadSnapshot(bundle: bundle)
    }

    private static func loadSnapshot(bundle: Bundle) -> StudentFinanceSnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }

    static func statistic(for provinceCode: String, bundle: Bundle = .main) -> StudentFinanceProvinceStatistic? {
        snapshot(bundle: bundle)?
            .provinces
            .first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame }
    }

    static func sources(bundle: Bundle = .main) -> [StudentFinanceSource] {
        let snapshotSources = snapshot(bundle: bundle)?.sources ?? []
        return snapshotSources.isEmpty ? [fallbackSource] : snapshotSources
    }

    static func decode(data: Data) throws -> StudentFinanceSnapshot {
        try JSONDecoder().decode(StudentFinanceSnapshot.self, from: data)
    }

    static func academicYearLabel(_ academicYear: String) -> String {
        academicYear.replacingOccurrences(of: "/", with: "-")
    }
}
