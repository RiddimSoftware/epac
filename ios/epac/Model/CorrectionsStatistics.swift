//
//  CorrectionsStatistics.swift
//  epac
//

import Foundation

struct CorrectionsAnnualStatistic: Decodable, Identifiable {
    var id: String { fiscalYear }

    let fiscalYear: String
    let totalInCustody: Int
    let indigenousInCustody: Int
    let indigenousInCustodyPercent: Double
    let nonIndigenousInCustody: Int
    let notReadmittedFiveYearsPercent: Double
    let recidivismRatePercent: Double
    let careAndCustodySpending: Int
    let costPerInmate: Int

    enum CodingKeys: String, CodingKey {
        case fiscalYear = "fiscal_year"
        case totalInCustody = "total_in_custody"
        case indigenousInCustody = "indigenous_in_custody"
        case indigenousInCustodyPercent = "indigenous_in_custody_percent"
        case nonIndigenousInCustody = "non_indigenous_in_custody"
        case notReadmittedFiveYearsPercent = "not_readmitted_five_years_percent"
        case recidivismRatePercent = "recidivism_rate_percent"
        case careAndCustodySpending = "care_and_custody_spending"
        case costPerInmate = "cost_per_inmate"
    }
}

struct CorrectionsPopulationShare: Decodable {
    let year: String
    let population: Int
    let percentOfCanada: Double
    let sourceTitle: String
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case year
        case population
        case percentOfCanada = "percent_of_canada"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
    }
}

struct CorrectionsOCIHighlight: Decodable, Identifiable {
    var id: String { title }

    let title: String
    let summary: String
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case sourceURL = "source_url"
    }
}

struct CorrectionsSource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct CorrectionsSnapshot: Decodable {
    let referenceFiscalYear: String
    let source: CorrectionsSource
    let sources: [CorrectionsSource]
    let indigenousPopulationShare: CorrectionsPopulationShare
    let annualStatistics: [CorrectionsAnnualStatistic]
    let ociHighlights: [CorrectionsOCIHighlight]

    var latestAnnualStatistic: CorrectionsAnnualStatistic? { annualStatistics.last }

    enum CodingKeys: String, CodingKey {
        case referenceFiscalYear = "reference_fiscal_year"
        case source
        case sources
        case indigenousPopulationShare = "indigenous_population_share"
        case annualStatistics = "annual_statistics"
        case ociHighlights = "oci_highlights"
    }
}

enum CorrectionsStatisticsDatabase {
    private static let resourceName = "corrections-statistics"
    private static let mainSnapshot = loadSnapshot(bundle: .main)

    static let fallbackSource = CorrectionsSource(
        title: "CSC Departmental Results Report and Indigenous Corrections Accountability Framework",
        url: URL(string: "https://www.canada.ca/en/correctional-service/corporate/transparency/reporting/departmental-results-reports/2023-2024.html")!,
        note: "Federal corrections statistics are published annually."
    )

    static func snapshot(bundle: Bundle = .main) -> CorrectionsSnapshot? {
        if bundle === Bundle.main {
            return mainSnapshot
        }
        return loadSnapshot(bundle: bundle)
    }

    static func sources(bundle: Bundle = .main) -> [CorrectionsSource] {
        let snapshotSources = snapshot(bundle: bundle)?.sources ?? []
        return snapshotSources.isEmpty ? [fallbackSource] : snapshotSources
    }

    static func decode(data: Data) throws -> CorrectionsSnapshot {
        try JSONDecoder().decode(CorrectionsSnapshot.self, from: data)
    }

    static func fiscalYearLabel(_ fiscalYear: String) -> String {
        fiscalYear.replacingOccurrences(of: " to ", with: "-")
    }

    private static func loadSnapshot(bundle: Bundle) -> CorrectionsSnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }
}
