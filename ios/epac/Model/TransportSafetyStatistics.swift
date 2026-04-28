//
//  TransportSafetyStatistics.swift
//  epac
//

import Foundation

struct TransportSafetyModeYear: Decodable, Identifiable {
    var id: Int { year }

    let year: Int
    let occurrences: Int
    let accidents: Int
    let incidents: Int
    let fatalities: Int
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case year
        case occurrences
        case accidents
        case incidents
        case fatalities
        case sourceURL = "source_url"
    }
}

struct TransportSafetySource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct TransportSafetyDataset: Decodable, Identifiable {
    let id: String
    let title: String
    let url: URL
}

struct TransportSafetyHistoryYears: Decodable {
    let tsb: [Int]
    let road: [Int]
}

struct RoadSafetyNationalYear: Decodable, Identifiable {
    var id: Int { year }

    let year: Int
    let fatalities: Int
    let seriousInjuries: Int
    let totalInjuries: Int
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case year
        case fatalities
        case seriousInjuries = "serious_injuries"
        case totalInjuries = "total_injuries"
        case sourceURL = "source_url"
    }
}

struct RoadSafetyProvinceYear: Decodable, Identifiable {
    var id: Int { year }

    let year: Int
    let fatalitiesPer100k: Double
    let injuriesPer100k: Double
    let fatalitiesPerBillionVKT: Double
    let injuriesPerBillionVKT: Double
    let fatalitiesPer100kLicensedDrivers: Double
    let injuriesPer100kLicensedDrivers: Double
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case year
        case fatalitiesPer100k = "fatalities_per_100k"
        case injuriesPer100k = "injuries_per_100k"
        case fatalitiesPerBillionVKT = "fatalities_per_billion_vkt"
        case injuriesPerBillionVKT = "injuries_per_billion_vkt"
        case fatalitiesPer100kLicensedDrivers = "fatalities_per_100k_licensed_drivers"
        case injuriesPer100kLicensedDrivers = "injuries_per_100k_licensed_drivers"
        case sourceURL = "source_url"
    }
}

struct RoadSafetyProvinceStatistic: Decodable, Identifiable {
    var id: String { provinceCode }

    let province: String
    let provinceCode: String
    let referenceYear: Int
    let fatalitiesPer100k: Double
    let injuriesPer100k: Double
    let fatalitiesPerBillionVKT: Double
    let history: [RoadSafetyProvinceYear]

    enum CodingKeys: String, CodingKey {
        case province
        case provinceCode = "province_code"
        case referenceYear = "reference_year"
        case fatalitiesPer100k = "fatalities_per_100k"
        case injuriesPer100k = "injuries_per_100k"
        case fatalitiesPerBillionVKT = "fatalities_per_billion_vkt"
        case history
    }
}

struct TransportSafetyRoad: Decodable {
    let national: [RoadSafetyNationalYear]
    let provinces: [RoadSafetyProvinceStatistic]
}

struct TransportSafetySnapshot: Decodable {
    let generatedAt: String?
    let historyYears: TransportSafetyHistoryYears
    let source: TransportSafetySource
    let datasets: [TransportSafetyDataset]
    let modes: [String: [TransportSafetyModeYear]]
    let road: TransportSafetyRoad

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case historyYears = "history_years"
        case source
        case datasets
        case modes
        case road
    }
}

enum TransportSafetyStatisticsDatabase {
    private static let resourceName = "transport-safety-statistics"
    private static let mainSnapshot = loadSnapshot(bundle: .main)

    static let fallbackSource = TransportSafetySource(
        title: "TSB Annual Statistics and Transport Canada Road Safety",
        url: URL(string: "https://tsb.gc.ca/eng/stats/aviation/stats.html")!,
        note: "TSB annual summaries cover air, marine, and rail occurrences. Transport Canada publishes road casualty rates through the National Collision Database."
    )

    static func snapshot(bundle: Bundle = .main) -> TransportSafetySnapshot? {
        if bundle === Bundle.main {
            return mainSnapshot
        }
        return loadSnapshot(bundle: bundle)
    }

    private static func loadSnapshot(bundle: Bundle) -> TransportSafetySnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }

    static func roadStatistic(for provinceCode: String, bundle: Bundle = .main) -> RoadSafetyProvinceStatistic? {
        snapshot(bundle: bundle)?
            .road
            .provinces
            .first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame }
    }

    static func latestModeYear(_ mode: String, bundle: Bundle = .main) -> TransportSafetyModeYear? {
        snapshot(bundle: bundle)?
            .modes[mode]?
            .max { $0.year < $1.year }
    }

    static func latestRoadNational(bundle: Bundle = .main) -> RoadSafetyNationalYear? {
        snapshot(bundle: bundle)?
            .road
            .national
            .max { $0.year < $1.year }
    }

    static func decode(data: Data) throws -> TransportSafetySnapshot {
        try JSONDecoder().decode(TransportSafetySnapshot.self, from: data)
    }

    static func rateLabel(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}
