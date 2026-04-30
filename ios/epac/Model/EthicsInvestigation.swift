//
//  EthicsInvestigation.swift
//  epac
//

import Foundation

struct EthicsInvestigation: Decodable, Identifiable {
    var id: String { pageURL.absoluteString }

    let subjectLastName: String
    let subjectFullName: String
    let reportTitle: String
    let date: String
    let type: String
    let pageURL: URL

    enum CodingKeys: String, CodingKey {
        case subjectLastName = "subject_last_name"
        case subjectFullName = "subject_full_name"
        case reportTitle = "report_title"
        case date
        case type
        case pageURL = "page_url"
    }
}

struct EthicsInvestigationsSource: Decodable {
    let title: String
    let url: URL
    let note: String
}

struct EthicsInvestigationsSnapshot: Decodable {
    let source: EthicsInvestigationsSource
    let investigations: [EthicsInvestigation]
}

enum EthicsInvestigationsDatabase {
    private static let mainSnapshot: EthicsInvestigationsSnapshot? = loadSnapshot()

    static let commissionerURL = URL(string: "https://ciec-ccie.parl.gc.ca/en/investigations-enquetes/Pages/InvestReport-RapportEnquete.aspx")!
    static let registryURL = URL(string: "https://prciec-rpccie.parl.gc.ca/EN/PublicRegistries/Pages/PublicRegistryHome.aspx")!
    static let complianceStatusURL = URL(string: "https://ciec-ccie.parl.gc.ca/en/news-nouvelles/Pages/StatusReport-RapportEtape.aspx")!

    static func investigations(for lastName: String, bundle: Bundle = .main) -> [EthicsInvestigation] {
        (mainSnapshot ?? loadSnapshot(bundle: bundle))?
            .investigations
            .filter { $0.subjectLastName.caseInsensitiveCompare(lastName) == .orderedSame }
        ?? []
    }

    static func snapshot(bundle: Bundle = .main) -> EthicsInvestigationsSnapshot? {
        if bundle === Bundle.main { return mainSnapshot }
        return loadSnapshot(bundle: bundle)
    }

    private static func loadSnapshot(bundle: Bundle = .main) -> EthicsInvestigationsSnapshot? {
        let name = "ethics-investigations"
        guard let url = bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "data"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data: data)
    }

    static func decode(data: Data) throws -> EthicsInvestigationsSnapshot {
        try JSONDecoder().decode(EthicsInvestigationsSnapshot.self, from: data)
    }

    static func formattedDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.locale = Locale(identifier: "en_CA")
        out.timeZone = TimeZone(identifier: "UTC")
        return out.string(from: date)
    }
}
