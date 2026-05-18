//
//  BillsService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches bills from the Parliament of Canada LEGISinfo JSON endpoint.
//  Data traces entirely to parl.ca, an authoritative Parliament source.
//  No AI-generated content.
//

import Foundation

struct BillsService {

    // The LEGISinfo JSON endpoint requires no auth and returns public data.
    // URL template: /legisinfo/en/bills/json?parlsession=<parliament>-<session>
    private static func billsURL(parliament: Int, session: Int) -> URL? {
        URL(string: "https://www.parl.ca/legisinfo/en/bills/json?parlsession=\(parliament)-\(session)&load=yes")
    }

    private static let legisInfoBase = "https://www.parl.ca/legisinfo/en/bill"

    // MARK: - Public

    /// Fetches all bills for the given Parliament and session.
    /// Defaults to Parliament 45, session 1 (current as of the app's inception date).
    static func fetchBills(
        parliament: Int = 45,
        session: Int = 1,
        network: NetworkService = .shared
    ) async throws -> [Bill] {
        guard let url = billsURL(parliament: parliament, session: session) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rawBills = try JSONDecoder().decode([LEGISinfoBill].self, from: data)
        return rawBills
            .compactMap { bill($0, parliament: parliament, session: session) }
            .sorted { lhs, rhs in
                // Most-recently-active first.
                (lhs.introducedDate ?? .distantPast) > (rhs.introducedDate ?? .distantPast)
            }
    }

    // MARK: - Mapping

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
    }

    private static func bill(_ raw: LEGISinfoBill, parliament: Int, session: Int) -> Bill? {
        let number = raw.BillNumberFormatted
        guard !number.isEmpty else { return nil }

        let title: String
        if let short = raw.ShortTitleEn, !short.isEmpty {
            title = short
        } else if let long = raw.LongTitleEn, !long.isEmpty {
            title = long
        } else {
            return nil
        }

        let status: BillStatus
        let statusLower = (raw.CurrentStatusEn ?? "").lowercased()
        if raw.ReceivedRoyalAssentDateTime != nil || statusLower.contains("royal assent") {
            status = .royalAssent
        } else if statusLower.contains("defeat") {
            status = .defeated
        } else {
            status = .inProgress
        }

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

        let houseFirst = parseDate(raw.PassedHouseFirstReadingDateTime)
        let houseSecond = parseDate(raw.PassedHouseSecondReadingDateTime)
        let houseThird = parseDate(raw.PassedHouseThirdReadingDateTime)
        let senateFirst = parseDate(raw.PassedSenateFirstReadingDateTime)
        let senateSecond = parseDate(raw.PassedSenateSecondReadingDateTime)
        let senateThird = parseDate(raw.PassedSenateThirdReadingDateTime)
        let royalAssent = parseDate(raw.ReceivedRoyalAssentDateTime)

        let introducedDate: Date?
        switch (houseFirst, senateFirst) {
        case let (house?, senate?):
            introducedDate = house < senate ? house : senate
        case let (house?, nil):
            introducedDate = house
        case let (nil, senate?):
            introducedDate = senate
        case (nil, nil):
            introducedDate = nil
        }

        let isHouseOriginating = (raw.OriginatingChamberId ?? 1) == 1
        let stages: [BillStage]
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
/// Only the fields we use are decoded; unknown fields are ignored.
private struct LEGISinfoBill: Decodable {
    let BillNumberFormatted: String
    let LongTitleEn: String?
    let ShortTitleEn: String?
    let LatestCompletedMajorStageEn: String?
    let CurrentStatusEn: String?
    let BillTypeEn: String?
    let SponsorEn: String?
    let OriginatingChamberId: Int?
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
