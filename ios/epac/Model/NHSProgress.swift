//
//  NHSProgress.swift
//  epac
//

import Foundation

struct NHSProgram: Identifiable {
    let id: String
    let name: String
    let budgetBillions: Double
    let unitLabel: String           // e.g. "homes", "households"
    let targetUnits: Int
    let committedUnits: Int         // as of reportingPeriod
    let category: NHSCategory
    let reportingPeriod: String     // e.g. "FY 2022-23"
}

enum NHSCategory: String {
    case newConstruction  = "New construction"
    case repair           = "Repair / retrofit"
    case directBenefit    = "Direct financial support"
    case enabling         = "Enabling (zoning & permits)"
}

struct NHSYearlyProgress: Identifiable {
    var id: Int { fiscalYearEnd }
    let fiscalYearEnd: Int          // calendar year at March 31
    let cumulativeHomesCommitted: Int
}

/// Static data from CMHC National Housing Strategy Annual Progress Report 2023
/// (fiscal year ending March 31, 2023) and NHS Quarterly Report Q1 2024.
/// Source: https://www.cmhc-schl.gc.ca/nhs/guidepage-strategy
struct NHSProgressDatabase {

    // Original NHS 10-year targets (2017-2027)
    static let newHomesTarget      = 100_000
    static let repairedHomesTarget = 300_000
    static let totalHomesTarget    = 400_000   // new + repaired under core NHS programs

    static let sourceURL = URL(string: "https://www.cmhc-schl.gc.ca/nhs/guidepage-strategy")!
    static let progressReportURL = URL(string: "https://assets.cmhc-schl.gc.ca/sites/place-to-call-home/pdfs/progress/nhs-progress-quarterly-report-q1-2024-en.pdf")!
    static let dataSource = "CMHC — NHS Annual Progress Report 2023 / Q1 2024 Quarterly Report"
    static let reportingPeriod = "FY 2022-23 (as of March 31, 2023)"

    // swiftlint:disable no_magic_numbers
    static let programs: [NHSProgram] = [
        NHSProgram(
            id: "aclp",
            name: "Apartment Construction Loan Program",
            budgetBillions: 25.75,
            unitLabel: "rental units",
            targetUnits: 100_000,
            committedUnits: 85_000,
            category: .newConstruction,
            reportingPeriod: "FY 2022-23"
        ),
        NHSProgram(
            id: "ncif-new",
            name: "National Co-Investment Fund — New",
            budgetBillions: 5.8,
            unitLabel: "new homes",
            targetUnits: 60_000,
            committedUnits: 54_000,
            category: .newConstruction,
            reportingPeriod: "FY 2022-23"
        ),
        NHSProgram(
            id: "ncif-repair",
            name: "National Co-Investment Fund — Repair",
            budgetBillions: 7.4,
            unitLabel: "repaired homes",
            targetUnits: 240_000,
            committedUnits: 196_000,
            category: .repair,
            reportingPeriod: "FY 2022-23"
        ),
        NHSProgram(
            id: "rhi",
            name: "Rapid Housing Initiative",
            budgetBillions: 4.0,
            unitLabel: "homes",
            targetUnits: 15_000,
            committedUnits: 14_709,
            category: .newConstruction,
            reportingPeriod: "All 3 phases, FY 2022-23"
        ),
        NHSProgram(
            id: "chb",
            name: "Canada Housing Benefit",
            budgetBillions: 2.5,
            unitLabel: "households",
            targetUnits: 300_000,
            committedUnits: 270_000,
            category: .directBenefit,
            reportingPeriod: "FY 2022-23"
        ),
        NHSProgram(
            id: "haf",
            name: "Housing Accelerator Fund",
            budgetBillions: 4.0,
            unitLabel: "homes enabled",
            targetUnits: 100_000,
            committedUnits: 40_000,
            category: .enabling,
            reportingPeriod: "Dec 2023 (179 municipal agreements)"
        ),
        NHSProgram(
            id: "innovation",
            name: "Affordable Housing Innovation Fund",
            budgetBillions: 0.2,
            unitLabel: "new units",
            targetUnits: 4_000,
            committedUnits: 3_500,
            category: .newConstruction,
            reportingPeriod: "FY 2022-23"
        )
    ]
    // swiftlint:enable no_magic_numbers

    // Cumulative homes committed under core NHS construction/repair programs
    // (ACLP + NCIF + RHI + Innovation), reported annually in NHS Annual Progress Reports.
    // swiftlint:disable no_magic_numbers
    static let yearlyProgress: [NHSYearlyProgress] = [
        NHSYearlyProgress(fiscalYearEnd: 2021, cumulativeHomesCommitted: 103_000),
        NHSYearlyProgress(fiscalYearEnd: 2022, cumulativeHomesCommitted: 194_000),
        NHSYearlyProgress(fiscalYearEnd: 2023, cumulativeHomesCommitted: 353_000)
    ]
    // swiftlint:enable no_magic_numbers

    // Sum of committed units across unit-producing programs (construction + repair)
    static var totalCommitted: Int {
        programs
            .filter { $0.category == .newConstruction || $0.category == .repair }
            .map(\.committedUnits)
            .reduce(0, +)
    }
}
