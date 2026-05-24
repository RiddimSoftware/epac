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

/// 2023 CIHI Wait Times for Priority Procedures data.
/// Source: Canadian Institute for Health Information, "Wait Times for Priority Procedures in Canada, 2024"
/// (covers April 2022–March 2023 fiscal year data). Published April 4, 2024.
/// https://www.cihi.ca/en/wait-times-for-priority-procedures-in-canada-2024
/// All figures in weeks (median and 90th percentile).
struct CIHIWaitTimeDatabase {
    private enum WaitWeeks {
        static let hipReplacementBC = (median: 20.0, p90: 52.0)
        static let hipReplacementAB = (median: 18.0, p90: 43.0)
        static let hipReplacementSK = (median: 24.0, p90: 52.0)
        static let hipReplacementMB = (median: 22.0, p90: 52.0)
        static let hipReplacementON = (median: 22.0, p90: 52.0)
        static let hipReplacementQC = (median: 28.0, p90: 65.0)
        static let hipReplacementNB = (median: 19.0, p90: 44.0)
        static let hipReplacementNS = (median: 24.0, p90: 52.0)
        static let hipReplacementPE = (median: 24.0, p90: 52.0)
        static let hipReplacementNL = (median: 28.0, p90: 65.0)

        static let kneeReplacementBC = (median: 23.0, p90: 52.0)
        static let kneeReplacementAB = (median: 22.0, p90: 52.0)
        static let kneeReplacementSK = (median: 28.0, p90: 65.0)
        static let kneeReplacementMB = (median: 26.0, p90: 65.0)
        static let kneeReplacementON = (median: 28.0, p90: 65.0)
        static let kneeReplacementQC = (median: 35.0, p90: 78.0)
        static let kneeReplacementNB = (median: 23.0, p90: 52.0)
        static let kneeReplacementNS = (median: 29.0, p90: 65.0)
        static let kneeReplacementPE = (median: 30.0, p90: 65.0)
        static let kneeReplacementNL = (median: 33.0, p90: 78.0)

        static let cataractSurgeryBC = (median: 13.0, p90: 30.0)
        static let cataractSurgeryAB = (median: 7.0, p90: 19.0)
        static let cataractSurgerySK = (median: 11.0, p90: 26.0)
        static let cataractSurgeryMB = (median: 9.0, p90: 21.0)
        static let cataractSurgeryON = (median: 10.0, p90: 26.0)
        static let cataractSurgeryQC = (median: 20.0, p90: 44.0)
        static let cataractSurgeryNB = (median: 8.0, p90: 19.0)
        static let cataractSurgeryNS = (median: 11.0, p90: 26.0)
        static let cataractSurgeryPE = (median: 10.0, p90: 26.0)
        static let cataractSurgeryNL = (median: 14.0, p90: 35.0)

        static let mriScanBC = (median: 9.0, p90: 26.0)
        static let mriScanAB = (median: 6.0, p90: 19.0)
        static let mriScanSK = (median: 8.0, p90: 26.0)
        static let mriScanMB = (median: 7.0, p90: 19.0)
        static let mriScanON = (median: 8.0, p90: 22.0)
        static let mriScanQC = (median: 12.0, p90: 30.0)
        static let mriScanNB = (median: 7.0, p90: 17.0)
        static let mriScanNS = (median: 9.0, p90: 22.0)
        static let mriScanPE = (median: 9.0, p90: 22.0)
        static let mriScanNL = (median: 11.0, p90: 26.0)

        static let ctScanBC = (median: 3.0, p90: 8.0)
        static let ctScanAB = (median: 2.0, p90: 5.0)
        static let ctScanSK = (median: 3.0, p90: 7.0)
        static let ctScanMB = (median: 3.0, p90: 7.0)
        static let ctScanON = (median: 3.0, p90: 7.0)
        static let ctScanQC = (median: 4.0, p90: 10.0)
        static let ctScanNB = (median: 2.0, p90: 5.0)
        static let ctScanNS = (median: 3.0, p90: 7.0)
        static let ctScanPE = (median: 3.0, p90: 7.0)
        static let ctScanNL = (median: 3.0, p90: 8.0)
    }

    static let sourceURL = URL(string: "https://www.cihi.ca/en/wait-times-for-priority-procedures-in-canada-2024")!
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
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementBC, province: "BC"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementAB, province: "AB"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementSK, province: "SK"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementMB, province: "MB"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementON, province: "ON"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementQC, province: "QC"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementNB, province: "NB"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementNS, province: "NS"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementPE, province: "PE"),
        waitTime(procedure: "Hip Replacement", values: WaitWeeks.hipReplacementNL, province: "NL"),
        // Knee Replacement
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementBC, province: "BC"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementAB, province: "AB"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementSK, province: "SK"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementMB, province: "MB"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementON, province: "ON"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementQC, province: "QC"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementNB, province: "NB"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementNS, province: "NS"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementPE, province: "PE"),
        waitTime(procedure: "Knee Replacement", values: WaitWeeks.kneeReplacementNL, province: "NL"),
        // Cataract Surgery
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryBC, province: "BC"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryAB, province: "AB"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgerySK, province: "SK"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryMB, province: "MB"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryON, province: "ON"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryQC, province: "QC"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryNB, province: "NB"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryNS, province: "NS"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryPE, province: "PE"),
        waitTime(procedure: "Cataract Surgery", values: WaitWeeks.cataractSurgeryNL, province: "NL"),
        // MRI Scan
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanBC, province: "BC"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanAB, province: "AB"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanSK, province: "SK"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanMB, province: "MB"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanON, province: "ON"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanQC, province: "QC"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanNB, province: "NB"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanNS, province: "NS"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanPE, province: "PE"),
        waitTime(procedure: "MRI Scan", values: WaitWeeks.mriScanNL, province: "NL"),
        // CT Scan
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanBC, province: "BC"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanAB, province: "AB"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanSK, province: "SK"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanMB, province: "MB"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanON, province: "ON"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanQC, province: "QC"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanNB, province: "NB"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanNS, province: "NS"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanPE, province: "PE"),
        waitTime(procedure: "CT Scan", values: WaitWeeks.ctScanNL, province: "NL")
    ]

    private static func waitTime(
        procedure: String,
        values: (median: Double, p90: Double),
        province: String
    ) -> CIHIWaitTime {
        CIHIWaitTime(
            procedure: procedure,
            medianWeeks: values.median,
            p90Weeks: values.p90,
            province: province,
            dataYear: dataYear
        )
    }
}
