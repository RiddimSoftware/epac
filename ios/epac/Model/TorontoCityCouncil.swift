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
            (.housing, ["housing", "rental", "affordable", "tenant"]),
            (.development, ["zoning", "rezoning", "development", "heritage"]),
            (.transportation, ["transit", "transportation", "bike", "cycling", "traffic", "parking"]),
            (.environment, ["environment", "climate", "tree", "green", "park"]),
            (.finance, ["budget", "finance", "tax", "fee", "grant"]),
            (.social, ["homelessness", "shelter", "social", "community", "food"])
        ]
    }
}

// MARK: - TorontoCouncilService

struct TorontoCouncilService {
    private static let councillorsCacheKey = "epac.toronto.councillors"
    private static let councillorsTSKey = "epac.toronto.councillors.ts"
    private static let votesCacheKey = "epac.toronto.votes"
    private static let votesTSKey = "epac.toronto.votes.ts"
    private enum Constants {
        static let secondsPerDay: TimeInterval = 86_400
        static let councillorsCacheDurationDays: TimeInterval = 7
        static let successfulHTTPStatusCodes = 200..<300
    }

    private enum WardNumber: Int {
        case etobicokeNorth = 1
        case etobicokeCentre = 2
        case etobicokeLakeshore = 3
        case parkdaleHighPark = 4
        case yorkSouthWeston = 5
        case yorkCentre = 6
        case humberRiverBlackCreek = 7
        case eglintonLawrence = 8
        case davenport = 9
        case spadinaFortYork = 10
        case universityRosedale = 11
        case torontoStPauls = 12
        case torontoCentre = 13
        case torontoDanforth = 14
        case donValleyWest = 15
        case donValleyEast = 16
        case donValleyNorth = 17
        case willowdale = 18
        case beachesEastYork = 19
        case scarboroughSouthwest = 20
        case scarboroughCentre = 21
        case scarboroughAgincourt = 22
        case scarboroughNorth = 23
        case scarboroughGuildwood = 24
        case scarboroughRougePark = 25
    }

    private static let councillorsTTL: TimeInterval = Constants.councillorsCacheDurationDays * Constants.secondsPerDay
    private static let votesTTL: TimeInterval = Constants.secondsPerDay

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
            .filter { _, wardName, _, _ in
                normalized.contains(normalize(wardName)) || normalize(wardName).contains(normalized)
            }
            .map { $0.0.rawValue }
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
              let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              Constants.successfulHTTPStatusCodes.contains(http.statusCode),
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
            let wardNumber = ward.rawValue
            return TorontoCouncillor(
                id: "ward-\(wardNumber)-\(lastName.lowercased().replacingOccurrences(of: " ", with: "-"))",
                firstName: firstName,
                lastName: lastName,
                wardNumber: wardNumber,
                wardName: wardName,
                party: "Independent",
                role: "Councillor",
                email: nil,
                profileURL: URL(string: "https://www.toronto.ca/city-government/council/members-of-council/councillor-ward-\(wardNumber)/") ?? councilURL
            )
        }
    }

    private static let wardCouncillors: [(WardNumber, String, String, String)] = [
        (.etobicokeNorth, "Etobicoke North", "Vincent", "Crisanti"),
        (.etobicokeCentre, "Etobicoke Centre", "Stephen", "Holyday"),
        (.etobicokeLakeshore, "Etobicoke-Lakeshore", "Amber", "Morley"),
        (.parkdaleHighPark, "Parkdale-High Park", "Gord", "Perks"),
        (.yorkSouthWeston, "York South-Weston", "Frances", "Nunziata"),
        (.yorkCentre, "York Centre", "James", "Pasternak"),
        (.humberRiverBlackCreek, "Humber River-Black Creek", "Anthony", "Perruzza"),
        (.eglintonLawrence, "Eglinton-Lawrence", "Mike", "Colle"),
        (.davenport, "Davenport", "Alejandra", "Bravo"),
        (.spadinaFortYork, "Spadina-Fort York", "Ausma", "Malik"),
        (.universityRosedale, "University-Rosedale", "Dianne", "Saxe"),
        (.torontoStPauls, "Toronto-St. Paul's", "Josh", "Matlow"),
        (.torontoCentre, "Toronto Centre", "Chris", "Moise"),
        (.torontoDanforth, "Toronto-Danforth", "Paula", "Fletcher"),
        (.donValleyWest, "Don Valley West", "Rachel", "Chernos Lin"),
        (.donValleyEast, "Don Valley East", "Jon", "Burnside"),
        (.donValleyNorth, "Don Valley North", "Shelley", "Carroll"),
        (.willowdale, "Willowdale", "Lily", "Cheng"),
        (.beachesEastYork, "Beaches-East York", "Brad", "Bradford"),
        (.scarboroughSouthwest, "Scarborough Southwest", "Parthi", "Kandavel"),
        (.scarboroughCentre, "Scarborough Centre", "Michael", "Thompson"),
        (.scarboroughAgincourt, "Scarborough-Agincourt", "Nick", "Mantas"),
        (.scarboroughNorth, "Scarborough North", "Jamaal", "Myers"),
        (.scarboroughGuildwood, "Scarborough-Guildwood", "Paul", "Ainslie"),
        (.scarboroughRougePark, "Scarborough-Rouge Park", "Neethan", "Shan")
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
