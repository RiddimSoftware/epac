//
//  EPetition.swift
//  epac
//
//  Created on 2026-04-27.
//

import Foundation
import SwiftUI

struct EPetition: Identifiable {
    let id: String           // petition number, e.g. "e-7344"
    let subject: String      // category / topic (e.g. "Transportation")
    let keywords: [String]   // related keywords from the search listing
    let sponsorName: String  // presenting MP
    let signatureCount: Int
    let deadline: Date?
    let status: PetitionStatus
    let petitionURL: URL     // official page on petitions.ourcommons.ca
}

enum PetitionStatus: String {
    case open = "Open"
    case closed = "Closed"
    case certified = "Certified"
    case responseReceived = "Response Received"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .open:             return NSLocalizedString("petition.status.open", comment: "")
        case .closed:           return NSLocalizedString("petition.status.closed", comment: "")
        case .certified:        return NSLocalizedString("petition.status.certified", comment: "")
        case .responseReceived: return NSLocalizedString("petition.status.responseReceived", comment: "")
        case .unknown:          return NSLocalizedString("petition.status.unknown", comment: "")
        }
    }

    var color: Color {
        switch self {
        case .open:             return Color(UIColor.systemGreen)
        case .certified:        return Color(UIColor.systemBlue)
        case .responseReceived: return Color(UIColor.systemPurple)
        default:                return Color(UIColor.systemGray)
        }
    }
}
