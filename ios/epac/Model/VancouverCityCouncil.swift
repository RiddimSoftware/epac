//
//  VancouverCityCouncil.swift
//  epac
//
//  Plain Codable value types for Vancouver City Council data.
//  Not SwiftData models — cached in UserDefaults, same pattern as OntarioLegislature.
//

import Foundation

struct VancouverCouncillor: Identifiable, Codable {
    let id: String
    let firstName: String
    let lastName: String
    var name: String { "\(firstName) \(lastName)" }
    let party: String       // "ABC", "Green", "Independent"
    let role: String        // "Mayor" or "Councillor"
    let email: String?
    let profileURL: URL
}

struct VancouverCouncilVote: Identifiable, Codable {
    let id: String
    let voteNumber: String
    let motionTitle: String
    let date: Date
    let councillorFirstName: String
    let councillorLastName: String
    var councillorName: String { "\(councillorFirstName) \(councillorLastName)" }
    let voteDetail: String  // "In Favour", "Opposed", "Absent", "Abstain"
    let category: VoteCategory

    enum VoteCategory: String, Codable, CaseIterable {
        case housing       = "Housing"
        case development   = "Development"
        case transportation = "Transportation"
        case environment   = "Environment"
        case finance       = "Finance"
        case social        = "Social Services"
        case other         = "Other"

        static func classify(_ title: String) -> VoteCategory {
            let title = title.lowercased()
            return category(for: title)
        }

        private static func category(for title: String) -> VoteCategory {
            for (category, keywords) in categoryKeywords {
                if titleContainsAnyKeyword(title, keywords: keywords) {
                    return category
                }
            }
            return .other
        }

        private static func titleContainsAnyKeyword(_ title: String, keywords: [String]) -> Bool {
            keywords.contains { title.contains($0) }
        }

        private static let categoryKeywords: [(VoteCategory, [String])] = [
            (.housing, ["housing", "rental", "affordable"]),
            (.development, ["zoning", "rezoning", "development", "heritage"]),
            (.transportation, ["transit", "transportation", "bike", "cycling", "traffic"]),
            (.environment, ["environment", "climate", "tree", "green", "park"]),
            (.finance, ["budget", "finance", "tax", "fee", "grant"]),
            (.social, ["homelessness", "shelter", "social", "community"])
        ]
    }
}

// MARK: - VancouverCouncilService

struct VancouverCouncilService {
    private static let councillorsCacheKey  = "epac.vancouver.councillors"
    private static let councillorsTSKey     = "epac.vancouver.councillors.ts"
    private static let votesCacheKey        = "epac.vancouver.votes"
    private static let votesTSKey           = "epac.vancouver.votes.ts"
    // swiftlint:disable:next no_magic_numbers
    private static let councillorsTTL: TimeInterval = 7 * 86_400   // 1 week
    private static let votesTTL: TimeInterval       = 86_400        // 1 day

    // MARK: - Public API

    static func fetchCouncillors() async -> [VancouverCouncillor] {
        if let cached = loadCouncillorsFromCache() { return cached }
        let councillors = await fetchCouncillorsFromOpenData() ?? staticCouncillorSeed()
        saveCouncillorsToCache(councillors)
        return councillors
    }

    static func fetchRecentVotes(limit: Int = 200) async -> [VancouverCouncilVote] {
        if let cached = loadVotesFromCache() { return cached }
        let votes = await fetchVotesFromOpenData(limit: limit) ?? []
        if !votes.isEmpty { saveVotesToCache(votes) }
        return votes
    }

    /// True when the federal riding name suggests a Vancouver city riding.
    static func isVancouverRiding(_ ridingName: String) -> Bool {
        ridingName.localizedCaseInsensitiveContains("Vancouver")
    }

    // MARK: - Open Data fetch (Vancouver Open Data portal, Socrata v2.1)

    private static func fetchCouncillorsFromOpenData() async -> [VancouverCouncillor]? {
        // Extract unique councillors from recent vote records — most reliable source.
        // swiftlint:disable:next no_magic_numbers
        let votes = (await fetchVotesFromOpenData(limit: 500)) ?? []
        guard !votes.isEmpty else { return nil }

        var seen = Set<String>()
        var councillors: [VancouverCouncillor] = []
        for vote in votes {
            let key = "\(vote.councillorFirstName)-\(vote.councillorLastName)".lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let party = partyFor(lastName: vote.councillorLastName)
            let role = vote.councillorLastName.lowercased() == "sim" ? "Mayor" : "Councillor"
            // swiftlint:disable:next force_unwrapping
            let profileURL = URL(string: "https://vancouver.ca/your-government/city-council.aspx")!
            councillors.append(VancouverCouncillor(
                id: key,
                firstName: vote.councillorFirstName,
                lastName: vote.councillorLastName,
                party: party,
                role: role,
                email: nil,
                profileURL: profileURL
            ))
        }
        return councillors.isEmpty ? nil : councillors
    }

    private static func fetchVotesFromOpenData(limit: Int) async -> [VancouverCouncilVote]? {
        let urlStr = "https://opendata.vancouver.ca/api/explore/v2.1/catalog/datasets/council-voting-records/records?limit=\(limit)&order_by=vote_date%20desc"
        guard let url = URL(string: urlStr),
              let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              // swiftlint:disable:next no_magic_numbers
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackParser = ISO8601DateFormatter()

        return results.compactMap { record -> VancouverCouncilVote? in
            guard let voteNumber  = record["vote_number"]       as? String,
                  let description = record["agenda_description"] as? String,
                  let firstName   = record["vote_first_name"]   as? String,
                  let lastName    = record["vote_last_name"]    as? String,
                  let detail      = record["vote_detail"]       as? String,
                  let dateStr     = record["vote_date"]         as? String else { return nil }
            let date = dateParser.date(from: dateStr) ?? fallbackParser.date(from: dateStr) ?? Date.distantPast
            let id = "\(voteNumber)-\(lastName.lowercased())"
            return VancouverCouncilVote(
                id: id,
                voteNumber: voteNumber,
                motionTitle: description,
                date: date,
                councillorFirstName: firstName,
                councillorLastName: lastName,
                voteDetail: detail,
                category: .classify(description)
            )
        }
    }

    // MARK: - Static seed (2022 council term, Sim mayoralty)

    // swiftlint:disable:next force_unwrapping
    private static let councilURL = URL(string: "https://vancouver.ca/your-government/city-council.aspx")!

    private static func staticCouncillorSeed() -> [VancouverCouncillor] {
        let members: [(String, String, String, String)] = [
            // (firstName, lastName, party, role)
            ("Ken", "Sim", "ABC", "Mayor"),
            ("Sarah", "Kirby-Yung", "ABC", "Councillor"),
            ("Lenny", "Zhou", "ABC", "Councillor"),
            ("Brian", "Montague", "ABC", "Councillor"),
            ("Rebecca", "Bligh", "ABC", "Councillor"),
            ("Mike", "Klassen", "ABC", "Councillor"),
            ("Lisa", "Dominato", "ABC", "Councillor"),
            ("Peter", "Meiszner", "ABC", "Councillor"),
            ("Melissa", "De Genova", "ABC", "Councillor"),
            ("Diego", "Cardona", "Green", "Councillor"),
            ("Pete", "Fry", "Green", "Councillor")
        ]
        return members.map { (fn, ln, party, role) in
            VancouverCouncillor(
                id: "\(fn)-\(ln)".lowercased().replacingOccurrences(of: " ", with: "-"),
                firstName: fn,
                lastName: ln,
                party: party,
                role: role,
                email: nil,
                profileURL: councilURL
            )
        }
    }

    private static func partyFor(lastName: String) -> String {
        let abcMembers = ["sim", "kirby-yung", "zhou", "montague", "bligh", "klassen", "dominato", "meiszner", "de genova"]
        let greenMembers = ["cardona", "fry"]
        let ln = lastName.lowercased()
        if abcMembers.contains(where: { ln.contains($0) }) { return "ABC" }
        if greenMembers.contains(where: { ln.contains($0) }) { return "Green" }
        return "Independent"
    }

    // MARK: - Cache

    private static func loadCouncillorsFromCache() -> [VancouverCouncillor]? {
        guard let data = UserDefaults.standard.data(forKey: councillorsCacheKey),
              let ts   = UserDefaults.standard.object(forKey: councillorsTSKey) as? Date,
              Date().timeIntervalSince(ts) < councillorsTTL,
              let list = try? JSONDecoder().decode([VancouverCouncillor].self, from: data)
        else { return nil }
        return list
    }

    private static func saveCouncillorsToCache(_ list: [VancouverCouncillor]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: councillorsCacheKey)
        UserDefaults.standard.set(Date(), forKey: councillorsTSKey)
    }

    private static func loadVotesFromCache() -> [VancouverCouncilVote]? {
        guard let data = UserDefaults.standard.data(forKey: votesCacheKey),
              let ts   = UserDefaults.standard.object(forKey: votesTSKey) as? Date,
              Date().timeIntervalSince(ts) < votesTTL,
              let list = try? JSONDecoder().decode([VancouverCouncilVote].self, from: data)
        else { return nil }
        return list
    }

    private static func saveVotesToCache(_ list: [VancouverCouncilVote]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: votesCacheKey)
        UserDefaults.standard.set(Date(), forKey: votesTSKey)
    }
}
