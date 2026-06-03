//
//  WitnessOrganizationService.swift
//  epac
//
//  Created on 2026-06-03.
//
//  Builds WitnessOrganization aggregates from CommitteeMeeting collections.
//  Organization name normalization is case-insensitive; ambiguous aliases are
//  surfaced in the maintenance log rather than auto-merged.
//

import Foundation

struct WitnessOrganizationService {

    /// Builds a `WitnessOrganization` for `organizationName` from the given meetings.
    /// Returns nil if no witnesses from that organization appear in any meeting.
    static func build(organizationName: String, from meetings: [CommitteeMeeting]) -> WitnessOrganization? {
        let key = normalizedKey(organizationName)
        guard !key.isEmpty else { return nil }

        let relevant = meetings.filter { meeting in
            meeting.witnesses.contains { normalizedKey($0.organization) == key }
        }
        guard !relevant.isEmpty else { return nil }

        let appearances: [CommitteeAppearance] = relevant.compactMap { meeting in
            let orgWitnesses = meeting.witnesses.filter { normalizedKey($0.organization) == key }
            guard !orgWitnesses.isEmpty else { return nil }
            return CommitteeAppearance(
                committeeId: meeting.committee,
                committeeName: meeting.committeeName,
                hearingDate: meeting.date,
                subjects: meeting.agendaItems,
                meetingNumber: meeting.meetingNumber,
                parliament: meeting.parliament,
                sessionNumber: meeting.sessionNumber,
                publicationURL: meeting.publicationURL ?? meeting.evidenceURL,
                witnesses: orgWitnesses
            )
        }.sorted { ($0.hearingDate ?? .distantPast) > ($1.hearingDate ?? .distantPast) }

        guard !appearances.isEmpty else { return nil }

        var seenNames = Set<String>()
        let individualWitnesses = appearances
            .flatMap(\.witnesses)
            .filter { seenNames.insert($0.name.lowercased()).inserted }

        return WitnessOrganization(
            id: key,
            displayName: organizationName,
            appearances: appearances,
            individualWitnesses: individualWitnesses,
            lobbyingCount: 0
        )
    }

    /// Aggregates all organizations across the given meetings, sorted by appearance count descending.
    /// Organizations with no name are skipped.
    static func aggregate(from meetings: [CommitteeMeeting]) -> [WitnessOrganization] {
        var groupedMeetings: [String: (displayName: String, meetings: [CommitteeMeeting])] = [:]

        for meeting in meetings {
            for witness in meeting.witnesses {
                let orgName = witness.organization.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !orgName.isEmpty else { continue }
                let key = normalizedKey(orgName)
                if groupedMeetings[key] == nil {
                    groupedMeetings[key] = (orgName, [])
                }
                if !groupedMeetings[key]!.meetings.contains(where: { $0.id == meeting.id }) {
                    groupedMeetings[key]!.meetings.append(meeting)
                }
            }
        }

        return groupedMeetings.compactMap { _, value in
            build(organizationName: value.displayName, from: value.meetings)
        }.sorted { $0.totalAppearances > $1.totalAppearances }
    }

    static func normalizedKey(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
