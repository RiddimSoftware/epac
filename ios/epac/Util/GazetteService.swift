import Foundation

// Fetches Canada Gazette notices from the official RSS feeds.
// Source: canadagazette.gc.ca — authoritative Government of Canada publication.
// No AI-generated content.

struct GazetteService {

    private static let partIURL  = URL(string: "https://canadagazette.gc.ca/rss/p1-en.xml")!
    private static let partIIURL = URL(string: "https://canadagazette.gc.ca/rss/p2-en.xml")!

    // MARK: - Public

    static func fetchAll() async throws -> [GazetteEntry] {
        async let partI  = fetch(url: partIURL,  part: .partI)
        async let partII = fetch(url: partIIURL, part: .partII)
        let (i, ii) = try await (partI, partII)
        return (i + ii).sorted { $0.publicationDate > $1.publicationDate }
    }

    static func fetch(part: GazettePart) async throws -> [GazetteEntry] {
        let url = part == .partI ? partIURL : partIIURL
        return try await fetch(url: url, part: part)
    }

    // MARK: - Private

    private static func fetch(url: URL, part: GazettePart) async throws -> [GazetteEntry] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return GazetteRSSParser.parse(data: data, part: part)
    }
}

// MARK: - RSS Parser

private final class GazetteRSSParser: NSObject, XMLParserDelegate {

    static func parse(data: Data, part: GazettePart) -> [GazetteEntry] {
        let parser = GazetteRSSParser(part: part)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.entries
    }

    private let part: GazettePart
    private var entries: [GazetteEntry] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentCategory = ""
    private var inItem = false

    private let rfc822Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private init(part: GazettePart) {
        self.part = part
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            inItem = true
            currentTitle = ""; currentLink = ""; currentDescription = ""
            currentPubDate = ""; currentCategory = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "link":        currentLink += string
        case "description": currentDescription += string
        case "pubDate":     currentPubDate += string
        case "category":    currentCategory += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard elementName == "item", inItem else { return }
        inItem = false

        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkStr = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let url = URL(string: linkStr) else { return }

        let date = rfc822Formatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .now
        let summary = currentDescription
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let category = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = linkStr

        entries.append(GazetteEntry(
            id: id,
            title: title,
            url: url,
            publicationDate: date,
            part: part,
            category: category,
            summary: summary
        ))
    }
}
