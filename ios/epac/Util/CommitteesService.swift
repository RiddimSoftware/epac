//
//  CommitteesService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches committee data from the OurCommons open API.
//  Endpoint: https://api.open.ourcommons.ca/ocd/
//  All data traces to an authoritative Parliament of Canada source.
//
//  API discovery notes (2026-04-27):
//  - /ocd/committees/ returns a paginated list of committees with id, acronymEn, longNameEn
//  - /ocd/committees/{id}/meetings/ returns paginated meetings per committee
//  - Evidence/interventions endpoint may not exist; if absent the UI falls back
//    to showing meeting metadata + a deep-link to parl.ca
//

import Foundation

struct CommitteesService {
    private static let baseURL = URL(string: "https://api.open.ourcommons.ca")!

    struct CommitteeMeetingsResult: Sendable {
        let upcoming: [CommitteeMeeting]
        let recent: [CommitteeMeeting]
    }

    // MARK: - Committees list

    /// Returns all House of Commons committees for the given parliament.
    /// Returns [] on any network or parse failure.
    static func fetchCommittees(parliament: Int = 45) async -> [ParliamentaryCommittee] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("ocd/committees/"),
            resolvingAgainstBaseURL: false
        ) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "parliament", value: String(parliament)),
            URLQueryItem(name: "chamber", value: "HOC"),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> ParliamentaryCommittee? in
            // API may return id or committeeCode as the identifier
            guard let id = item["id"] as? String ?? item["committeeCode"] as? String,
                  let name = item["longNameEn"] as? String ?? item["nameEn"] as? String
            else { return nil }
            let acronym = item["acronymEn"] as? String ?? item["committeeCode"] as? String ?? ""
            let chamber = item["chamberCode"] as? String ?? "HOC"
            let urlStr = item["url"] as? String
                ?? "https://www.ourcommons.ca/committees/en/\(acronym)"
            let committeeURL = URL(string: urlStr) ?? URL(string: "https://www.ourcommons.ca")!
            return ParliamentaryCommittee(
                id: id, acronym: acronym, name: name,
                chamberCode: chamber, committeeURL: committeeURL
            )
        }
    }

    // MARK: - Meetings for a committee

    /// Returns the most recent meetings for a given committee.
    /// Returns [] on any network or parse failure.
    static func fetchRecentMeetings(committeeId: String, parliament: Int = 45) async -> [CommitteeMeeting] {
        let meetings = await fetchMeetings(committeeId: committeeId, parliament: parliament)
        return meetings.recent
    }

    /// Returns upcoming and recent meetings for a given committee.
    /// Returns empty sections on any network or parse failure.
    static func fetchMeetings(
        committeeId: String,
        parliament: Int = 45,
        now: Date = Date()
    ) async -> CommitteeMeetingsResult {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("ocd/committees/\(committeeId)/meetings/"),
            resolvingAgainstBaseURL: false
        ) else { return CommitteeMeetingsResult(upcoming: [], recent: []) }
        components.queryItems = [
            URLQueryItem(name: "parliament", value: String(parliament)),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return CommitteeMeetingsResult(upcoming: [], recent: []) }

        return parseMeetings(items, committeeId: committeeId, parliament: parliament, now: now)
    }

    static func parseMeetings(
        _ items: [[String: Any]],
        committeeId: String,
        parliament: Int,
        now: Date
    ) -> CommitteeMeetingsResult {
        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let meetings = items.compactMap { item -> CommitteeMeeting? in
            let meetingNum = item["number"] as? Int ?? item["meetingNumber"] as? Int ?? 0
            let sessionNum = item["session"] as? Int ?? item["sessionNumber"] as? Int ?? 1
            let parl = item["parliament"] as? Int ?? parliament
            let dateStr = item["startDateTime"] as? String ?? item["date"] as? String ?? ""
            // Try fractional-seconds ISO 8601 first, then without
            let date = isoParser.date(from: dateStr) ?? {
                let fallback = ISO8601DateFormatter()
                fallback.formatOptions = [.withInternetDateTime]
                return fallback.date(from: dateStr)
            }()
            let committeeName = item["committeeNameEn"] as? String ?? ""
            let agenda = parseAgendaItems(from: item)
            let pubURLStr = item["publicationUrl"] as? String ?? item["url"] as? String
            let pubURL = pubURLStr.flatMap { URL(string: $0) }
            let evidenceURLStr = item["evidenceUrl"] as? String
            let evidenceURL = evidenceURLStr.flatMap { URL(string: $0) }
            let witnesses = parseWitnesses(from: item)
            let webcastURL = firstURL(
                in: item,
                keys: [
                    "webcastUrl", "webcastURL", "webcastUrlEn", "webcastURLEN",
                    "recordingUrl", "recordingURL", "recordingUrlEn",
                    "parlVuUrl", "parlVUUrl", "parlvuUrl", "videoUrl"
                ]
            )
            return CommitteeMeeting(
                id: "\(committeeId)-\(parl)-\(sessionNum)-\(meetingNum)",
                committee: committeeId,
                committeeName: committeeName,
                meetingNumber: meetingNum,
                sessionNumber: sessionNum,
                parliament: parl,
                date: date,
                agendaItems: agenda,
                witnesses: witnesses,
                webcastURL: webcastURL,
                publicationURL: pubURL,
                evidenceURL: evidenceURL
            )
        }
        let upcoming = meetings
            .filter { ($0.date ?? .distantPast) >= now }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let recent = meetings
            .filter { ($0.date ?? .distantPast) < now }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return CommitteeMeetingsResult(upcoming: upcoming, recent: recent)
    }

    // MARK: - Interventions (evidence) for a meeting

    /// Returns individual interventions (speeches) from a committee meeting.
    /// Returns [] if the evidence endpoint doesn't exist or parse fails.
    /// The caller should fall back to showing meeting metadata + a link to parl.ca.
    ///
    /// Note: the API path uses the numeric meeting number, not the composite
    /// `CommitteeMeeting.id` string (which is an app-internal key, not an API token).
    static func fetchInterventions(committeeId: String, meetingNumber: Int) async -> [CommitteeIntervention] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "ocd/committees/\(committeeId)/meetings/\(meetingNumber)/evidence/"
            ),
            resolvingAgainstBaseURL: false
        ) else { return [] }
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components.url,
              let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [] }

        return items.enumerated().compactMap { (idx, item) -> CommitteeIntervention? in
            let name = item["speakerNameEn"] as? String
                ?? item["speakerName"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            let role = item["roleName"] as? String
                ?? item["speakerRole"] as? String ?? "Member"
            let affiliation = item["affiliationNameEn"] as? String
                ?? item["partyName"] as? String ?? ""
            let isMP = item["isMP"] as? Bool
                ?? (item["memberTypeCode"] as? String == "MP")
            let content = item["contentEn"] as? String
                ?? item["content"] as? String ?? ""
            let ts = item["timestamp"] as? String
            return CommitteeIntervention(
                id: "\(committeeId)-\(meetingNumber)-\(idx)",
                speakerName: name,
                speakerRole: role,
                affiliation: affiliation,
                isMP: isMP,
                content: content,
                timestamp: ts
            )
        }
    }

    private static func firstURL(in item: [String: Any], keys: [String]) -> URL? {
        for key in keys {
            if let value = item[key] as? String,
               let url = ParlVULinkBuilder.normalizedURL(from: value) {
                return url
            }
        }
        return nil
    }

    private static func parseWitnesses(from item: [String: Any]) -> [CommitteeWitness] {
        let possibleCollections = [
            "witnesses", "witnessList", "scheduledWitnesses", "participants"
        ]
        for key in possibleCollections {
            if let values = item[key] as? [[String: Any]] {
                return values.compactMap(parseWitness)
            }
        }
        return []
    }

    private static func parseAgendaItems(from item: [String: Any]) -> [String] {
        if let values = item["agendaItems"] as? [[String: Any]] {
            return values.compactMap {
                firstString(in: $0, keys: ["titleEn", "title", "nameEn", "name"])
            }
        }
        if let values = item["agendaItems"] as? [String] {
            return values
        }
        return []
    }

    private static func parseWitness(_ item: [String: Any]) -> CommitteeWitness? {
        let name = firstString(
            in: item,
            keys: ["nameEn", "fullNameEn", "personNameEn", "witnessNameEn", "name", "fullName", "personName"]
        )
        guard let name, !name.isEmpty else { return nil }
        let organization = firstString(
            in: item,
            keys: [
                "organizationEn", "organizationNameEn", "affiliationEn",
                "organization", "organizationName", "affiliation"
            ]
        ) ?? ""
        return CommitteeWitness(name: name, organization: organization)
    }

    private static func firstString(in item: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = item[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
