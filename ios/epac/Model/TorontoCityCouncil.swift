//
//  TorontoCityCouncil.swift
//  epac
//
//  Plain Codable value types for Toronto City Council data.
//  Not SwiftData models; cached in UserDefaults like Vancouver council data.
//

import Foundation

struct TorontoCouncillor: Identifiable, Codable {
    let id: String
    let firstName: String
    let lastName: String
    let wardNumber: Int?
    let wardName: String
    var name: String { "\(firstName) \(lastName)" }
    let party: String
    let role: String
    let email: String?
    let profileURL: URL
}

struct TorontoCouncilVote: Identifiable, Codable {
    let id: String
    let agendaItemNumber: String
    let agendaItemTitle: String
    let motionType: String
    let voteDescription: String
    let result: String
    let date: Date
    let councillorFirstName: String
    let councillorLastName: String
    var councillorName: String { "\(councillorFirstName) \(councillorLastName)" }
    let voteDetail: String
    let category: VoteCategory

    enum VoteCategory: String, Codable, CaseIterable {
        case housing = "Housing"
        case development = "Development"
        case transportation = "Transportation"
        case environment = "Environment"
        case finance = "Finance"
        case social = "Social Services"
        case other = "Other"

        static func classify(_ title: String) -> VoteCategory {
            let t = title.lowercased()
            if t.contains("housing") || t.contains("rental") || t.contains("affordable") || t.contains("tenant") {
                return .housing
            }
            if t.contains("zoning") || t.contains("rezoning") || t.contains("development") || t.contains("heritage") {
                return .development
            }
            if t.contains("transit") || t.contains("transportation") || t.contains("bike") || t.contains("cycling") || t.contains("traffic") || t.contains("parking") {
                return .transportation
            }
            if t.contains("environment") || t.contains("climate") || t.contains("tree") || t.contains("green") || t.contains("park") {
                return .environment
            }
            if t.contains("budget") || t.contains("finance") || t.contains("tax") || t.contains("fee") || t.contains("grant") {
                return .finance
            }
            if t.contains("homelessness") || t.contains("shelter") || t.contains("social") || t.contains("community") || t.contains("food") {
                return .social
            }
            return .other
        }
    }
}

// MARK: - TorontoCouncilService

struct TorontoCouncilService {
    private static let councillorsCacheKey = "epac.toronto.councillors"
    private static let councillorsTSKey = "epac.toronto.councillors.ts"
    private static let votesCacheKey = "epac.toronto.votes"
    private static let votesTSKey = "epac.toronto.votes.ts"
    private static let councillorsTTL: TimeInterval = 7 * 86_400
    private static let votesTTL: TimeInterval = 86_400

    private static let voteResourceID = "55ead013-2331-4686-9895-9e8145b94189"
    private static let openDataBase = "https://ckan0.cf.opendata.inter.prod-toronto.ca/api/3/action/datastore_search"

    static func fetchCouncillors() async -> [TorontoCouncillor] {
        if let cached = loadCouncillorsFromCache() { return cached }
        let councillors = staticCouncillorSeed()
        saveCouncillorsToCache(councillors)
        return councillors
    }

    static func fetchRecentVotes(limit: Int = 250) async -> [TorontoCouncilVote] {
        if let cached = loadVotesFromCache() { return cached }
        let votes = await fetchVotesFromOpenData(limit: limit) ?? []
        if !votes.isEmpty { saveVotesToCache(votes) }
        return votes
    }

    /// True when the saved federal riding name is likely inside Toronto.
    static func isTorontoRiding(_ ridingName: String) -> Bool {
        let normalized = ridingName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return torontoRidingHints.contains { normalized.contains($0) }
    }

    static func councillors(for ridingName: String, in councillors: [TorontoCouncillor]) -> [TorontoCouncillor] {
        let normalized = normalize(ridingName)
        let matchedWards = wardCouncillors
            .filter { ward, wardName, _, _ in
                normalized.contains(normalize(wardName)) || normalize(wardName).contains(normalized)
            }
            .map { $0.0 }
        guard !matchedWards.isEmpty else { return councillors }
        return councillors.filter { councillor in
            guard let ward = councillor.wardNumber else { return false }
            return matchedWards.contains(ward)
        }
    }

    // MARK: - Open Data fetch

    private static func fetchVotesFromOpenData(limit: Int) async -> [TorontoCouncilVote]? {
        var components = URLComponents(string: openDataBase)
        components?.queryItems = [
            URLQueryItem(name: "resource_id", value: voteResourceID),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "Date/Time desc")
        ]
        guard let url = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let records = result["records"] as? [[String: Any]] else { return nil }

        return parseVoteRecords(records)
    }

    static func parseVoteRecords(_ records: [[String: Any]]) -> [TorontoCouncilVote] {
        records.compactMap { record -> TorontoCouncilVote? in
            guard let idValue = record["_id"],
                  let firstName = stringField(record, "First Name"),
                  let lastName = stringField(record, "Last Name"),
                  let agendaItemNumber = stringField(record, "Agenda Item #"),
                  let agendaItemTitle = stringField(record, "Agenda Item Title"),
                  let vote = stringField(record, "Vote") else { return nil }

            let motionType = stringField(record, "Motion Type") ?? ""
            let result = stringField(record, "Result") ?? ""
            let voteDescription = stringField(record, "Vote Description") ?? agendaItemTitle
            let date = parseDate(stringField(record, "Date/Time") ?? "")
            let sourceID = "\(idValue)"

            return TorontoCouncilVote(
                id: sourceID,
                agendaItemNumber: agendaItemNumber,
                agendaItemTitle: agendaItemTitle,
                motionType: motionType,
                voteDescription: voteDescription,
                result: result,
                date: date,
                councillorFirstName: firstName,
                councillorLastName: lastName,
                voteDetail: normalizeVote(vote),
                category: .classify("\(agendaItemTitle) \(voteDescription)")
            )
        }
    }

    private static func stringField(_ record: [String: Any], _ key: String) -> String? {
        guard let value = record[key] else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return "\(value)"
    }

    private static func parseDate(_ value: String) -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutMeridiem = trimmed
            .replacingOccurrences(of: " AM", with: "")
            .replacingOccurrences(of: " PM", with: "")
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_CA_POSIX")
        parser.timeZone = TimeZone(identifier: "America/Toronto")
        for candidate in [trimmed, withoutMeridiem] {
            for format in ["yyyy-MM-dd HH:mm a", "yyyy-MM-dd h:mm a", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                parser.dateFormat = format
                if let date = parser.date(from: candidate) { return date }
            }
        }
        return Date.distantPast
    }

    private static func normalizeVote(_ vote: String) -> String {
        switch vote.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes": return "Yes"
        case "no": return "No"
        case "absent": return "Absent"
        case let value where value.contains("conflict"): return "Conflict"
        default: return vote
        }
    }

    // MARK: - Static seed

    private static let councilURL = URL(string: "https://www.toronto.ca/city-government/council/members-of-council/")!

    private static func staticCouncillorSeed() -> [TorontoCouncillor] {
        let mayor = TorontoCouncillor(
            id: "mayor-olivia-chow",
            firstName: "Olivia",
            lastName: "Chow",
            wardNumber: nil,
            wardName: "City-wide",
            party: "Independent",
            role: "Mayor",
            email: nil,
            profileURL: councilURL
        )
        return [mayor] + wardCouncillors.map { ward, wardName, firstName, lastName in
            TorontoCouncillor(
                id: "ward-\(ward)-\(lastName.lowercased().replacingOccurrences(of: " ", with: "-"))",
                firstName: firstName,
                lastName: lastName,
                wardNumber: ward,
                wardName: wardName,
                party: "Independent",
                role: "Councillor",
                email: nil,
                profileURL: URL(string: "https://www.toronto.ca/city-government/council/members-of-council/councillor-ward-\(ward)/") ?? councilURL
            )
        }
    }

    private static let wardCouncillors: [(Int, String, String, String)] = [
        (1, "Etobicoke North", "Vincent", "Crisanti"),
        (2, "Etobicoke Centre", "Stephen", "Holyday"),
        (3, "Etobicoke-Lakeshore", "Amber", "Morley"),
        (4, "Parkdale-High Park", "Gord", "Perks"),
        (5, "York South-Weston", "Frances", "Nunziata"),
        (6, "York Centre", "James", "Pasternak"),
        (7, "Humber River-Black Creek", "Anthony", "Perruzza"),
        (8, "Eglinton-Lawrence", "Mike", "Colle"),
        (9, "Davenport", "Alejandra", "Bravo"),
        (10, "Spadina-Fort York", "Ausma", "Malik"),
        (11, "University-Rosedale", "Dianne", "Saxe"),
        (12, "Toronto-St. Paul's", "Josh", "Matlow"),
        (13, "Toronto Centre", "Chris", "Moise"),
        (14, "Toronto-Danforth", "Paula", "Fletcher"),
        (15, "Don Valley West", "Rachel", "Chernos Lin"),
        (16, "Don Valley East", "Jon", "Burnside"),
        (17, "Don Valley North", "Shelley", "Carroll"),
        (18, "Willowdale", "Lily", "Cheng"),
        (19, "Beaches-East York", "Brad", "Bradford"),
        (20, "Scarborough Southwest", "Parthi", "Kandavel"),
        (21, "Scarborough Centre", "Michael", "Thompson"),
        (22, "Scarborough-Agincourt", "Nick", "Mantas"),
        (23, "Scarborough North", "Jamaal", "Myers"),
        (24, "Scarborough-Guildwood", "Paul", "Ainslie"),
        (25, "Scarborough-Rouge Park", "Neethan", "Shan")
    ]

    private static let torontoRidingHints = [
        "toronto", "etobicoke", "york", "humber river", "eglington", "eglinton",
        "davenport", "spadina", "fort york", "university", "rosedale",
        "parkdale", "high park", "don valley", "willowdale", "beaches",
        "scarborough", "rouge park", "agincourt"
    ]

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cache

    private static func loadCouncillorsFromCache() -> [TorontoCouncillor]? {
        guard let data = UserDefaults.standard.data(forKey: councillorsCacheKey),
              let ts = UserDefaults.standard.object(forKey: councillorsTSKey) as? Date,
              Date().timeIntervalSince(ts) < councillorsTTL,
              let list = try? JSONDecoder().decode([TorontoCouncillor].self, from: data)
        else { return nil }
        return list
    }

    private static func saveCouncillorsToCache(_ list: [TorontoCouncillor]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: councillorsCacheKey)
        UserDefaults.standard.set(Date(), forKey: councillorsTSKey)
    }

    private static func loadVotesFromCache() -> [TorontoCouncilVote]? {
        guard let data = UserDefaults.standard.data(forKey: votesCacheKey),
              let ts = UserDefaults.standard.object(forKey: votesTSKey) as? Date,
              Date().timeIntervalSince(ts) < votesTTL,
              let list = try? JSONDecoder().decode([TorontoCouncilVote].self, from: data)
        else { return nil }
        return list
    }

    private static func saveVotesToCache(_ list: [TorontoCouncilVote]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: votesCacheKey)
        UserDefaults.standard.set(Date(), forKey: votesTSKey)
    }
}
