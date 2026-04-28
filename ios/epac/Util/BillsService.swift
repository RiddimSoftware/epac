//
//  BillsService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches bills from the Parliament of Canada LEGISinfo JSON endpoint.
//  Data traces entirely to parl.ca — an authoritative Parliament source.
//  No AI-generated content.
//

import Foundation

struct BillsService {

    // The LEGISinfo JSON endpoint — no auth required, public data.
    // URL template: /legisinfo/en/bills/json?parlsession=<parliament>-<session>
    private static func billsURL(parliament: Int, session: Int) -> URL? {
        URL(string: "https://www.parl.ca/legisinfo/en/bills/json?parlsession=\(parliament)-\(session)&load=yes")
    }

    private static let legisInfoBase = "https://www.parl.ca/legisinfo/en/bill"

    // MARK: - Public

    /// Fetches all bills for the given Parliament and session.
    /// Defaults to Parliament 45, session 1 (current as of the app's inception date).
    static func fetchBills(parliament: Int = 45, session: Int = 1) async throws -> [Bill] {
        guard let url = billsURL(parliament: parliament, session: session) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rawBills = try JSONDecoder().decode([LEGISinfoBill].self, from: data)
        return rawBills.compactMap { bill($0, parliament: parliament, session: session) }
                       .sorted { lhs, rhs in
                           // Most-recently-active first
                           (lhs.introducedDate ?? .distantPast) > (rhs.introducedDate ?? .distantPast)
                       }
    }

    // MARK: - Mapping

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        // ISO 8601 with fractional seconds (e.g. "2025-05-27T08:44:38.9-04:00")
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    private static func bill(_ raw: LEGISinfoBill, parliament: Int, session: Int) -> Bill? {
        let number = raw.BillNumberFormatted
        guard !number.isEmpty else { return nil }

        // Title: prefer short title if present, otherwise long title
        let title: String
        if let short = raw.ShortTitleEn, !short.isEmpty {
            title = short
        } else if let long = raw.LongTitleEn, !long.isEmpty {
            title = long
        } else {
            return nil
        }

        // Status
        let status: BillStatus
        let statusLower = (raw.CurrentStatusEn ?? "").lowercased()
        if raw.ReceivedRoyalAssentDateTime != nil || statusLower.contains("royal assent") {
            status = .royalAssent
        } else if statusLower.contains("defeat") {
            status = .defeated
        } else {
            status = .inProgress
        }

        // Bill type
        let billType: BillType
        let typeLower = (raw.BillTypeEn ?? "").lowercased()
        if typeLower.contains("house government") {
            billType = .houseGovernment
        } else if typeLower.contains("private member") {
            billType = .privateMember
        } else if typeLower.contains("senate government") {
            billType = .senateGovernment
        } else if typeLower.contains("senate public") {
            billType = .senatePublic
        } else if typeLower.contains("senate private") {
            billType = .senatePrivate
        } else {
            billType = .unknown
        }

        // Dates
        let houseFirst  = parseDate(raw.PassedHouseFirstReadingDateTime)
        let houseSecond = parseDate(raw.PassedHouseSecondReadingDateTime)
        let houseThird  = parseDate(raw.PassedHouseThirdReadingDateTime)
        let senateFirst = parseDate(raw.PassedSenateFirstReadingDateTime)
        let senateSecond = parseDate(raw.PassedSenateSecondReadingDateTime)
        let senateThird = parseDate(raw.PassedSenateThirdReadingDateTime)
        let royalAssent = parseDate(raw.ReceivedRoyalAssentDateTime)

        // Introduced date: whichever first reading came first
        let introducedDate: Date?
        switch (houseFirst, senateFirst) {
        case let (h?, s?): introducedDate = h < s ? h : s
        case let (h?, nil): introducedDate = h
        case let (nil, s?): introducedDate = s
        case (nil, nil): introducedDate = nil
        }

        // Build stage timeline
        // For House-originating bills: House 1st → House 2nd → House 3rd → Senate 1st → Senate 3rd → Royal Assent
        // For Senate-originating bills: Senate 1st → Senate 3rd → House 1st → House 3rd → Royal Assent
        let isHouseOriginating = (raw.OriginatingChamberId ?? 1) == 1
        var stages: [BillStage]
        if isHouseOriginating {
            stages = [
                makeStage(id: "\(number)-h1", nameKey: "bills.stage.houseFirst", date: houseFirst),
                makeStage(id: "\(number)-h2", nameKey: "bills.stage.houseSecond", date: houseSecond),
                makeStage(id: "\(number)-h3", nameKey: "bills.stage.houseThird", date: houseThird),
                makeStage(id: "\(number)-s1", nameKey: "bills.stage.senateFirst", date: senateFirst),
                makeStage(id: "\(number)-s2", nameKey: "bills.stage.senateSecond", date: senateSecond),
                makeStage(id: "\(number)-s3", nameKey: "bills.stage.senateThird", date: senateThird),
                makeStage(id: "\(number)-ra", nameKey: "bills.stage.royalAssent", date: royalAssent)
            ]
        } else {
            stages = [
                makeStage(id: "\(number)-s1", nameKey: "bills.stage.senateFirst", date: senateFirst),
                makeStage(id: "\(number)-s2", nameKey: "bills.stage.senateSecond", date: senateSecond),
                makeStage(id: "\(number)-s3", nameKey: "bills.stage.senateThird", date: senateThird),
                makeStage(id: "\(number)-h1", nameKey: "bills.stage.houseFirst", date: houseFirst),
                makeStage(id: "\(number)-h2", nameKey: "bills.stage.houseSecond", date: houseSecond),
                makeStage(id: "\(number)-h3", nameKey: "bills.stage.houseThird", date: houseThird),
                makeStage(id: "\(number)-ra", nameKey: "bills.stage.royalAssent", date: royalAssent)
            ]
        }

        let currentStage = raw.LatestCompletedMajorStageEn ?? raw.CurrentStatusEn ?? ""

        // LEGISinfo detail URL  e.g. https://www.parl.ca/legisinfo/en/bill/45-1/c-5
        // Both components are hardcoded strings that always produce valid URLs,
        // but we guard instead of force-unwrapping so a future refactor can't crash.
        let billSlug = "\(parliament)-\(session)/\(number.lowercased())"
        guard let legisURL = URL(string: "\(legisInfoBase)/\(billSlug)")
                          ?? URL(string: legisInfoBase) else { return nil }

        return Bill(
            id: number,
            number: number,
            title: title,
            sponsorName: raw.SponsorEn ?? "",
            status: status,
            currentStage: currentStage,
            introducedDate: introducedDate,
            stages: stages,
            legisInfoURL: legisURL,
            billType: billType,
            parliament: parliament,
            session: session
        )
    }

    private static func makeStage(id: String, nameKey: String, date: Date?) -> BillStage {
        BillStage(
            id: id,
            name: NSLocalizedString(nameKey, comment: ""),
            completedDate: date,
            isCompleted: date != nil
        )
    }
}

// MARK: - Raw JSON shape from LEGISinfo

/// Mirrors the JSON object returned by the LEGISinfo bills endpoint.
/// Only the fields we use are decoded; unknown fields are silently ignored.
private struct LEGISinfoBill: Decodable {
    let BillNumberFormatted: String
    let LongTitleEn: String?
    let ShortTitleEn: String?
    let LatestCompletedMajorStageEn: String?
    let CurrentStatusEn: String?
    let BillTypeEn: String?
    let SponsorEn: String?
    let OriginatingChamberId: Int?      // 1 = House, 2 = Senate; nil-safe for future API changes
    let ParliamentNumber: Int
    let SessionNumber: Int

    let PassedHouseFirstReadingDateTime: String?
    let PassedHouseSecondReadingDateTime: String?
    let PassedHouseThirdReadingDateTime: String?
    let PassedSenateFirstReadingDateTime: String?
    let PassedSenateSecondReadingDateTime: String?
    let PassedSenateThirdReadingDateTime: String?
    let ReceivedRoyalAssentDateTime: String?
}
