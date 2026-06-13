//
//  Bill.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Plain value-type model for a bill from the Parliament of Canada LEGISinfo API.
//  Not a SwiftData model — bills are fetched fresh and not persisted locally.
//

import Foundation
import SwiftUI

// MARK: - Bill

struct Bill: Identifiable, Codable, Sendable {
    let id: String          // bill number e.g. "C-50", "S-12"
    let number: String      // same as id
    let title: String
    let sponsorName: String
    let status: BillStatus
    let currentStage: String
    let introducedDate: Date?
    let royalAssentDate: Date?
    let summary: String?
    let sponsorProfileURL: URL?
    let stages: [BillStage]
    let legisInfoURL: URL
    let type: BillType
    let parliament: Int
    let session: Int

    var becameLawDate: Date? {
        royalAssentDate ?? stages.first { $0.name.localizedCaseInsensitiveContains("royal assent") }?.completedDate
    }
}

// MARK: - BillStage

struct BillStage: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let completedDate: Date?
    let isCompleted: Bool
}

// MARK: - BillStatus

enum BillStatus: String, Codable, Equatable, Sendable {
    case inProgress  = "InProgress"
    case royalAssent = "RoyalAssent"
    case defeated    = "Defeated"
    case unknown     = "Unknown"

    var displayName: String {
        switch self {
        case .inProgress:  return NSLocalizedString("bill.status.inProgress", comment: "")
        case .royalAssent: return NSLocalizedString("bill.status.royalAssent", comment: "")
        case .defeated:    return NSLocalizedString("bill.status.defeated", comment: "")
        case .unknown:     return NSLocalizedString("bill.status.unknown", comment: "")
        }
    }

    var color: Color { Color.billStatus(self) }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let exact = BillStatus(rawValue: raw) {
            self = exact
            return
        }

        let normalized = raw.lowercased()
        if normalized.contains("royal assent") || normalized.contains("royalassent") {
            self = .royalAssent
        } else if normalized.contains("defeat") {
            self = .defeated
        } else if normalized.isEmpty {
            self = .unknown
        } else {
            self = .inProgress
        }
    }
}

// MARK: - BillType

// swiftlint:disable redundant_string_enum_value
enum BillType: String, Codable, Equatable, Sendable {
    case government        = "government"
    case privateMember     = "privateMember"
    case senatePublic      = "senatePublic"
    case senatePrivate     = "senatePrivate"
    case unknown           = "unknown"

    var displayName: String {
        switch self {
        case .government:       return NSLocalizedString("bill.type.government", comment: "")
        case .privateMember:    return NSLocalizedString("bill.type.privateMember", comment: "")
        case .senatePublic:     return NSLocalizedString("bill.type.senatePublic", comment: "")
        case .senatePrivate:    return NSLocalizedString("bill.type.senatePrivate", comment: "")
        case .unknown:          return ""
        }
    }

    /// Short label for compact display.
    var shortName: String {
        switch self {
        case .government:       return NSLocalizedString("bill.type.short.gov", comment: "")
        case .privateMember:    return NSLocalizedString("bill.type.short.pmb", comment: "")
        case .senatePublic,
             .senatePrivate:    return NSLocalizedString("bill.type.short.senate", comment: "")
        case .unknown:          return ""
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let exact = BillType(rawValue: raw) {
            self = exact
            return
        }

        let normalized = raw.lowercased()
        if normalized.contains("private member") {
            self = .privateMember
        } else if normalized.contains("senate private") {
            self = .senatePrivate
        } else if normalized.contains("senate public") {
            self = .senatePublic
        } else if normalized.contains("government") {
            self = .government
        } else {
            self = .unknown
        }
    }
}
// swiftlint:enable redundant_string_enum_value
