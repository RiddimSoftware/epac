//
//  RevolvingDoorMatch.swift
//  epac
//
//  Value types for the revolving door tracker: former MPs and ministers who
//  become registered lobbyists after leaving Parliament.
//
//  Data sources:
//    parl.ca / ourcommons.ca historical members list
//    Office of the Commissioner of Lobbying open dataset
//    https://lobbycanada.gc.ca/en/open-data/
//
//  All matching is high-confidence only; ambiguous matches require human
//  confirmation before being surfaced. Banner copy is strictly factual —
//  "Now a registered lobbyist", never "revolving door violation".
//

import Foundation

// MARK: - CoolingOffStatus

enum CoolingOffStatus: Equatable {
    /// Former DPOH whose registration date is > 5 years after leaving Parliament.
    case cooledOff
    /// Former DPOH whose registration date is ≤ 5 years after leaving Parliament.
    case withinCoolingOff(expiryDate: Date)
    /// Non-DPOH (backbench MP) — cooling-off calculation is not applicable.
    case notApplicable

    var label: String {
        switch self {
        case .cooledOff:            return "Cooled off"
        case .withinCoolingOff:     return "Within cooling-off period"
        case .notApplicable:        return "N/A — non-DPOH"
        }
    }
}

// MARK: - RevolvingDoorMatch

struct RevolvingDoorMatch: Identifiable {
    let id: String                              // member directoryKey
    let memberID: Int
    let memberName: String
    let formerRole: String
    let parliamentaryServiceStart: Date?
    let parliamentaryServiceEnd: Date?
    let firstLobbyistCommunicationDate: Date?
    let organizationName: String
    let subjectMatter: String
    let coolingOffStatus: CoolingOffStatus
    let registryURL: URL
    let sourceNote: String
}
