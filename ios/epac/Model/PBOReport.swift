//
//  PBOReport.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Plain value-type model for a Parliamentary Budget Officer publication.
//  Fetched from the PBO REST API; never persisted to SwiftData.
//

import Foundation

struct PBOReport: Identifiable {
    private enum EstimateParsing {
        static let trillionMultiplier: Double = 1_000_000_000_000
        static let billionMultiplier: Double = 1_000_000_000
        static let millionMultiplier: Double = 1_000_000
        static let numericPrefixLength = 20
        static let significantDisagreementThreshold = 0.10
    }

    /// Unique PBO internal ID, e.g. "LEG-2526-009-S"
    let id: String
    let title: String
    /// The matched bill number as supplied by the caller, e.g. "C-50"
    let billReference: String
    /// Formatted cost estimate from the PBO, if available (free-form text from abstract)
    let pboEstimate: String?
    /// Government's own estimate, if stated in the report (rarely present in API data)
    let governmentEstimate: String?
    let reportDate: Date?
    /// Canonical URL for the report on pbo-dpb.ca
    let reportURL: URL
    /// Abstract or description of the report
    let summary: String

    /// Returns true when both estimates are parseable and differ by more than 10%.
    var estimatesDisagreeSignificantly: Bool {
        guard let pboStr = pboEstimate, let govStr = governmentEstimate else { return false }
        let multipliers: [String: Double] = [
            "trillion": EstimateParsing.trillionMultiplier,
            "billion": EstimateParsing.billionMultiplier,
            "million": EstimateParsing.millionMultiplier
        ]
        func parse(_ s: String) -> Double? {
            let lower = s.lowercased()
            for (word, mult) in multipliers {
                if lower.contains(word) {
                    // Extract the leading numeric portion before any word boundary.
                    // Split on chars that are not digits, periods, or commas, then take the first
                    // non-empty token and strip commas so "1,234.5" parses correctly as 1234.5.
                    let separators = CharacterSet.decimalDigits
                        .union(CharacterSet(charactersIn: ".,"))
                        .inverted
                    let token = lower
                        .components(separatedBy: separators)
                        .first(where: { !$0.isEmpty }) ?? ""
                    let stripped = token.replacingOccurrences(of: ",", with: "")
                    if let num = Double(stripped.prefix(EstimateParsing.numericPrefixLength)) {
                        return num * mult
                    }
                }
            }
            return nil
        }
        guard let pbo = parse(pboStr),
              let gov = parse(govStr),
              gov > 0 else { return false }
        return abs(pbo - gov) / gov > EstimateParsing.significantDisagreementThreshold
    }
}
