//
//  EPetition.swift
//  epac
//
//  Created on 2026-04-27.
//

import Foundation
import SwiftUI

struct PetitionGovernmentResponse: Codable, Equatable {
    let text: String
    let tabledOn: Date
    let respondingMinister: String?
}

struct EPetition: Identifiable {
    let id: String           // petition number, e.g. "e-7344"
    let subject: String      // category / topic (e.g. "Transportation")
    let keywords: [String]   // related keywords from the search listing
    let sponsorName: String  // presenting MP
    let signatureCount: Int
    let deadline: Date?
    let status: PetitionStatus
    let petitionURL: URL     // official page on petitions.ourcommons.ca
    let governmentResponse: PetitionGovernmentResponse?

    init(
        id: String,
        subject: String,
        keywords: [String],
        sponsorName: String,
        signatureCount: Int,
        deadline: Date?,
        status: PetitionStatus,
        petitionURL: URL,
        governmentResponse: PetitionGovernmentResponse? = nil
    ) {
        self.id = id
        self.subject = subject
        self.keywords = keywords
        self.sponsorName = sponsorName
        self.signatureCount = signatureCount
        self.deadline = deadline
        self.status = status
        self.petitionURL = petitionURL
        self.governmentResponse = governmentResponse
    }
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

    // System colors — not party tokens; petition status uses its own semantic palette.
    var color: Color {
        switch self {
        case .open:             return Color(UIColor.systemGreen)
        case .certified:        return Color(UIColor.systemBlue)
        case .responseReceived: return Color(UIColor.systemPurple)
        default:                return Color(UIColor.systemGray)
        }
    }
}
