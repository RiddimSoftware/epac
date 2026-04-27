//
//  LobbyistCommunication.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Plain Codable struct representing a single communication report from the
//  Commissioner of Lobbying open dataset (communications_ocl_cal.zip).
//  No SwiftData — purely in-memory.
//
//  Data source: https://lobbycanada.gc.ca/en/open-data/
//  Authority:   Office of the Commissioner of Lobbying of Canada
//

import Foundation

struct LobbyistCommunication: Identifiable, Codable {
    let id: String                  // COMLOG_ID
    let lobbyistName: String        // "FirstName LastName"
    let organizationName: String    // EN_CLIENT_ORG_CORP_NM_AN
    let communicationDate: Date?    // COMM_DATE (yyyy-MM-dd)
    let subjectMatter: String       // comma-joined SMT descriptions
    let registrantType: String      // e.g. "Consultant", "In-house (organization)"
    let registryURL: URL            // link to the OCL search filtered to this MP
}
