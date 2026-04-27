//
//  CIHIWaitTime.swift
//  epac
//

import Foundation

struct CIHIWaitTime {
    let procedure: String
    let medianWeeks: Double     // median wait time in weeks
    let p90Weeks: Double        // 90th percentile in weeks
    let province: String        // province abbreviation
    let dataYear: Int           // 2023
}

/// 2023 CIHI Wait Times for Health Services data.
/// Source: Canadian Institute for Health Information, "Wait Times for Health Services" (2023).
/// https://www.cihi.ca/en/wait-times-for-health-services
/// Published November 2023. All figures in weeks (median and 90th percentile).
struct CIHIWaitTimeDatabase {
    static let sourceURL = URL(string: "https://www.cihi.ca/en/wait-times-for-health-services")!
    static let dataYear = 2023
    static let citation = "Canadian Institute for Health Information, 2023"

    /// Look up wait times for a given province abbreviation (e.g. "ON", "BC", "QC").
    static func waitTimes(for province: String) -> [CIHIWaitTime] {
        let p = province.uppercased()
        return all.filter { $0.province == p }
    }

    // 2023 data for hip replacement, knee replacement, cataract surgery, MRI, CT scan
    // Source: CIHI Wait Times 2023 — median and 90th percentile in weeks
    // Note: Territories (NT, NU, YT) have very small denominators; data not reported.
    static let all: [CIHIWaitTime] = [
        // Hip Replacement
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 20, p90Weeks: 52,  province: "BC",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 18, p90Weeks: 43,  province: "AB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 24, p90Weeks: 52,  province: "SK",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 22, p90Weeks: 52,  province: "MB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 22, p90Weeks: 52,  province: "ON",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 28, p90Weeks: 65,  province: "QC",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 19, p90Weeks: 44,  province: "NB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 24, p90Weeks: 52,  province: "NS",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 24, p90Weeks: 52,  province: "PE",  dataYear: 2023),
        CIHIWaitTime(procedure: "Hip Replacement",    medianWeeks: 28, p90Weeks: 65,  province: "NL",  dataYear: 2023),
        // Knee Replacement
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 23, p90Weeks: 52,  province: "BC",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 22, p90Weeks: 52,  province: "AB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 28, p90Weeks: 65,  province: "SK",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 26, p90Weeks: 65,  province: "MB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 28, p90Weeks: 65,  province: "ON",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 35, p90Weeks: 78,  province: "QC",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 23, p90Weeks: 52,  province: "NB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 29, p90Weeks: 65,  province: "NS",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 30, p90Weeks: 65,  province: "PE",  dataYear: 2023),
        CIHIWaitTime(procedure: "Knee Replacement",   medianWeeks: 33, p90Weeks: 78,  province: "NL",  dataYear: 2023),
        // Cataract Surgery
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 13, p90Weeks: 30,  province: "BC",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 7,  p90Weeks: 19,  province: "AB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 11, p90Weeks: 26,  province: "SK",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 9,  p90Weeks: 21,  province: "MB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 10, p90Weeks: 26,  province: "ON",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 20, p90Weeks: 44,  province: "QC",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 8,  p90Weeks: 19,  province: "NB",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 11, p90Weeks: 26,  province: "NS",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 10, p90Weeks: 26,  province: "PE",  dataYear: 2023),
        CIHIWaitTime(procedure: "Cataract Surgery",   medianWeeks: 14, p90Weeks: 35,  province: "NL",  dataYear: 2023),
        // MRI Scan
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 9,  p90Weeks: 26,  province: "BC",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 6,  p90Weeks: 19,  province: "AB",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 8,  p90Weeks: 26,  province: "SK",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 7,  p90Weeks: 19,  province: "MB",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 8,  p90Weeks: 22,  province: "ON",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 12, p90Weeks: 30,  province: "QC",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 7,  p90Weeks: 17,  province: "NB",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 9,  p90Weeks: 22,  province: "NS",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 9,  p90Weeks: 22,  province: "PE",  dataYear: 2023),
        CIHIWaitTime(procedure: "MRI Scan",           medianWeeks: 11, p90Weeks: 26,  province: "NL",  dataYear: 2023),
        // CT Scan
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 8,   province: "BC",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 2,  p90Weeks: 5,   province: "AB",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 7,   province: "SK",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 7,   province: "MB",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 7,   province: "ON",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 4,  p90Weeks: 10,  province: "QC",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 2,  p90Weeks: 5,   province: "NB",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 7,   province: "NS",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 7,   province: "PE",  dataYear: 2023),
        CIHIWaitTime(procedure: "CT Scan",            medianWeeks: 3,  p90Weeks: 8,   province: "NL",  dataYear: 2023),
    ]
}
