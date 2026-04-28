//
//  CommitteeEvidence.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Domain model for parliamentary committee data.
//  All data fetched from api.open.ourcommons.ca — an authoritative Parliament source.
//  No SwiftData: Codable structs only (meetings are ephemeral, not worth persisting).
//

import Foundation

struct ParliamentaryCommittee: Identifiable, Codable, Sendable {
    let id: String
    let acronym: String           // e.g. "FINA"
    let name: String              // e.g. "Standing Committee on Finance"
    let chamberCode: String       // "HOC" or "SEN"
    let committeeURL: URL
}

struct CommitteeMeeting: Identifiable, Codable, Sendable {
    let id: String
    let committee: String         // committee acronym / id
    let committeeName: String
    let meetingNumber: Int
    let sessionNumber: Int
    let parliament: Int
    let date: Date?
    let agendaItems: [String]     // list of agenda item titles
    let webcastURL: URL?          // ParlVU or official House embed watch URL
    let publicationURL: URL?      // link to full transcript on parl.ca
    let evidenceURL: URL?         // direct link to the evidence publication
}

struct CommitteeIntervention: Identifiable, Codable, Sendable {
    let id: String
    let speakerName: String
    let speakerRole: String       // e.g. "Chair", "Member", "Witness"
    let affiliation: String       // party for MPs, organization for witnesses
    let isMP: Bool
    let content: String           // the intervention text
    let timestamp: String?        // time of intervention if available
}
