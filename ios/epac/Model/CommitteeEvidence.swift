//
//  CommitteeEvidence.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Domain model for parliamentary committee data.
//  All data is sourced from api.openparliament.ca (documented open parliament source).
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
    let witnesses: [CommitteeWitness]
    let webcastURL: URL?          // ParlVU or official House embed watch URL
    let publicationURL: URL?      // link to full transcript on parl.ca
    let evidenceURL: URL?         // direct link to the evidence publication

    init(
        id: String,
        committee: String,
        committeeName: String,
        meetingNumber: Int,
        sessionNumber: Int,
        parliament: Int,
        date: Date?,
        agendaItems: [String],
        witnesses: [CommitteeWitness] = [],
        webcastURL: URL?,
        publicationURL: URL?,
        evidenceURL: URL?
    ) {
        self.id = id
        self.committee = committee
        self.committeeName = committeeName
        self.meetingNumber = meetingNumber
        self.sessionNumber = sessionNumber
        self.parliament = parliament
        self.date = date
        self.agendaItems = agendaItems
        self.witnesses = witnesses
        self.webcastURL = webcastURL
        self.publicationURL = publicationURL
        self.evidenceURL = evidenceURL
    }

    enum CodingKeys: CodingKey {
        case id
        case committee
        case committeeName
        case meetingNumber
        case sessionNumber
        case parliament
        case date
        case agendaItems
        case witnesses
        case webcastURL
        case publicationURL
        case evidenceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        committee = try container.decode(String.self, forKey: .committee)
        committeeName = try container.decode(String.self, forKey: .committeeName)
        meetingNumber = try container.decode(Int.self, forKey: .meetingNumber)
        sessionNumber = try container.decode(Int.self, forKey: .sessionNumber)
        parliament = try container.decode(Int.self, forKey: .parliament)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        agendaItems = try container.decode([String].self, forKey: .agendaItems)
        witnesses = try container.decodeIfPresent([CommitteeWitness].self, forKey: .witnesses) ?? []
        webcastURL = try container.decodeIfPresent(URL.self, forKey: .webcastURL)
        publicationURL = try container.decodeIfPresent(URL.self, forKey: .publicationURL)
        evidenceURL = try container.decodeIfPresent(URL.self, forKey: .evidenceURL)
    }
}

struct CommitteeWitness: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(name)-\(organization)" }
    let name: String
    let organization: String
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
