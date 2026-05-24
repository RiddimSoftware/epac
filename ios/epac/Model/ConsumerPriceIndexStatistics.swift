//
//  ConsumerPriceIndexStatistics.swift
//  epac
//

import Foundation

struct ConsumerPriceIndexMonth: Decodable, Identifiable {
    var id: String { refDate }

    let refDate: String
    let allItemsIndex: Double
    let allItemsYearOverYearPercent: Double
    let foodYearOverYearPercent: Double
    let shelterYearOverYearPercent: Double
    let energyYearOverYearPercent: Double

    enum CodingKeys: String, CodingKey {
        case refDate = "ref_date"
        case allItemsIndex = "all_items_index"
        case allItemsYearOverYearPercent = "all_items_yoy_percent"
        case foodYearOverYearPercent = "food_yoy_percent"
        case shelterYearOverYearPercent = "shelter_yoy_percent"
        case energyYearOverYearPercent = "energy_yoy_percent"
    }
}

struct ConsumerPriceIndexStatistic: Decodable, Identifiable {
    var id: String { provinceCode }

    let province: String
    let provinceCode: String
    let referenceMonth: String
    let allItemsIndex: Double
    let allItemsYearOverYearPercent: Double
    let foodYearOverYearPercent: Double
    let shelterYearOverYearPercent: Double
    let energyYearOverYearPercent: Double
    let nationalAllItemsYearOverYearPercent: Double
    let months: [ConsumerPriceIndexMonth]

    enum CodingKeys: String, CodingKey {
        case province
        case provinceCode = "province_code"
        case referenceMonth = "reference_month"
        case allItemsIndex = "all_items_index"
        case allItemsYearOverYearPercent = "all_items_yoy_percent"
        case foodYearOverYearPercent = "food_yoy_percent"
        case shelterYearOverYearPercent = "shelter_yoy_percent"
        case energyYearOverYearPercent = "energy_yoy_percent"
        case nationalAllItemsYearOverYearPercent = "national_all_items_yoy_percent"
        case months
    }
}

struct ConsumerPriceIndexSource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct ConsumerPriceIndexSnapshot: Decodable {
    let referenceMonth: String
    let source: ConsumerPriceIndexSource
    let national: ConsumerPriceIndexStatistic
    let provinces: [ConsumerPriceIndexStatistic]

    enum CodingKeys: String, CodingKey {
        case referenceMonth = "reference_month"
        case source
        case national
        case provinces
    }
}

enum ConsumerPriceIndexStatisticsDatabase {
    private static let resourceName = "cpi-statistics"
    private static let mainSnapshot = loadSnapshot(bundle: .main)
    private enum DateParsing {
        static let componentCount = 2
        static let validMonthRange = 1...12
        static let firstDayOfMonth = 1
        static let monthSymbolIndexOffset = 1
    }

    static let fallbackSource = ConsumerPriceIndexSource(
        title: "Statistics Canada — Consumer Price Index",
        url: URL(string: "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1810000401")!,
        note: "Monthly CPI table 18-10-0004-01 is not seasonally adjusted and normally published about three weeks after the reference month."
    )

    static func snapshot(bundle: Bundle = .main) -> ConsumerPriceIndexSnapshot? {
        if bundle === Bundle.main {
            return mainSnapshot
        }
        return loadSnapshot(bundle: bundle)
    }

    private static func loadSnapshot(bundle: Bundle) -> ConsumerPriceIndexSnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }

    static func statistic(for provinceCode: String, bundle: Bundle = .main) -> ConsumerPriceIndexStatistic? {
        snapshot(bundle: bundle)?
            .provinces
            .first { $0.provinceCode.caseInsensitiveCompare(provinceCode) == .orderedSame }
    }

    static func decode(data: Data) throws -> ConsumerPriceIndexSnapshot {
        try JSONDecoder().decode(ConsumerPriceIndexSnapshot.self, from: data)
    }

    static func date(for refDate: String) -> Date? {
        let parts = refDate.split(separator: "-")
        guard parts.count == DateParsing.componentCount,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              DateParsing.validMonthRange.contains(month) else {
            return nil
        }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: DateParsing.firstDayOfMonth))
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
