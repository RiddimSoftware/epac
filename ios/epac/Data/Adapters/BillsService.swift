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
    private enum Constants {
        static let currentParliament = 45
        static let currentSession = 1
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    // The LEGISinfo JSON endpoint requires no auth and returns public data.
    // URL template: /legisinfo/en/bills/json?parlsession=<parliament>-<session>
    private static func billsURL(parliament: Int, session: Int) -> URL? {
        URL(string: "https://www.parl.ca/legisinfo/en/bills/json?parlsession=\(parliament)-\(session)&load=yes")
    }

    private static let legisInfoBase = "https://www.parl.ca/legisinfo/en/bill"
    private static let houseChamberID = 1
    private static let billTypeMappings: [(needle: String, type: BillType)] = [
        ("house government", .houseGovernment),
        ("private member", .privateMember),
        ("senate government", .senateGovernment),
        ("senate public", .senatePublic),
        ("senate private", .senatePrivate)
    ]

    // MARK: - Public

    /// Fetches all bills for the given Parliament and session.
    /// Defaults to Parliament 45, session 1 (current as of the app's inception date).
    static func fetchBills(
        parliament: Int = Constants.currentParliament,
        session: Int = Constants.currentSession,
        network: NetworkService = .shared
    ) async throws -> [Bill] {
        guard let url = billsURL(parliament: parliament, session: session) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse, Constants.successStatusCodes.contains(http.statusCode) else {
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
        guard let title = billTitle(from: raw) else { return nil }

        let readingDates = billReadingDates(from: raw)
        let introducedDate = billIntroducedDate(from: readingDates)
        let stages = billStages(number: number, raw: raw, dates: readingDates)

        let currentStage = raw.LatestCompletedMajorStageEn ?? raw.CurrentStatusEn ?? ""
        let billSlug = "\(parliament)-\(session)/\(number.lowercased())"
        guard let legisURL = URL(string: "\(legisInfoBase)/\(billSlug)")
            ?? URL(string: legisInfoBase) else { return nil }

        return Bill(
            id: number,
            number: number,
            title: title,
            sponsorName: raw.SponsorEn ?? "",
            status: billStatus(from: raw),
            currentStage: currentStage,
            introducedDate: introducedDate,
            stages: stages,
            legisInfoURL: legisURL,
            billType: billType(from: raw),
            parliament: parliament,
            session: session
        )
    }

    private static func billTitle(from raw: LEGISinfoBill) -> String? {
        if let short = raw.ShortTitleEn, !short.isEmpty {
            return short
        }
        if let long = raw.LongTitleEn, !long.isEmpty {
            return long
        }
        return nil
    }

    private static func billStatus(from raw: LEGISinfoBill) -> BillStatus {
        let statusLower = (raw.CurrentStatusEn ?? "").lowercased()
        if raw.ReceivedRoyalAssentDateTime != nil || statusLower.contains("royal assent") {
            return .royalAssent
        }
        if statusLower.contains("defeat") {
            return .defeated
        }
        return .inProgress
    }

    private static func billType(from raw: LEGISinfoBill) -> BillType {
        let typeLower = (raw.BillTypeEn ?? "").lowercased()
        return billTypeMappings.first { typeLower.contains($0.needle) }?.type ?? .unknown
    }

    private static func billReadingDates(from raw: LEGISinfoBill) -> BillReadingDates {
        BillReadingDates(
            houseFirst: parseDate(raw.PassedHouseFirstReadingDateTime),
            houseSecond: parseDate(raw.PassedHouseSecondReadingDateTime),
            houseThird: parseDate(raw.PassedHouseThirdReadingDateTime),
            senateFirst: parseDate(raw.PassedSenateFirstReadingDateTime),
            senateSecond: parseDate(raw.PassedSenateSecondReadingDateTime),
            senateThird: parseDate(raw.PassedSenateThirdReadingDateTime),
            royalAssent: parseDate(raw.ReceivedRoyalAssentDateTime)
        )
    }

    private static func billIntroducedDate(from dates: BillReadingDates) -> Date? {
        [dates.houseFirst, dates.senateFirst].compactMap { $0 }.min()
    }

    private static func billStages(number: String, raw: LEGISinfoBill, dates: BillReadingDates) -> [BillStage] {
        let isHouseOriginating = (raw.OriginatingChamberId ?? houseChamberID) == houseChamberID
        return billStageSpecs(isHouseOriginating: isHouseOriginating).map { spec in
            makeStage(id: "\(number)-\(spec.suffix)", nameKey: spec.nameKey, date: spec.date(in: dates))
        }
    }

    private static func billStageSpecs(isHouseOriginating: Bool) -> [BillStageSpec] {
        if isHouseOriginating {
            return houseStageSpecs + senateStageSpecs + royalAssentStageSpecs
        }
        return senateStageSpecs + houseStageSpecs + royalAssentStageSpecs
    }

    private static func makeStage(id: String, nameKey: String, date: Date?) -> BillStage {
        BillStage(
            id: id,
            name: NSLocalizedString(nameKey, comment: ""),
            completedDate: date,
            isCompleted: date != nil
        )
    }

    private static let houseStageSpecs: [BillStageSpec] = [
        BillStageSpec(suffix: "h1", nameKey: "bills.stage.houseFirst", date: \.houseFirst),
        BillStageSpec(suffix: "h2", nameKey: "bills.stage.houseSecond", date: \.houseSecond),
        BillStageSpec(suffix: "h3", nameKey: "bills.stage.houseThird", date: \.houseThird)
    ]

    private static let senateStageSpecs: [BillStageSpec] = [
        BillStageSpec(suffix: "s1", nameKey: "bills.stage.senateFirst", date: \.senateFirst),
        BillStageSpec(suffix: "s2", nameKey: "bills.stage.senateSecond", date: \.senateSecond),
        BillStageSpec(suffix: "s3", nameKey: "bills.stage.senateThird", date: \.senateThird)
    ]

    private static let royalAssentStageSpecs: [BillStageSpec] = [
        BillStageSpec(suffix: "ra", nameKey: "bills.stage.royalAssent", date: \.royalAssent)
    ]
}

private struct BillReadingDates {
    let houseFirst: Date?
    let houseSecond: Date?
    let houseThird: Date?
    let senateFirst: Date?
    let senateSecond: Date?
    let senateThird: Date?
    let royalAssent: Date?
}

private struct BillStageSpec {
    let suffix: String
    let nameKey: String
    let date: KeyPath<BillReadingDates, Date?>

    func date(in dates: BillReadingDates) -> Date? {
        dates[keyPath: date]
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
