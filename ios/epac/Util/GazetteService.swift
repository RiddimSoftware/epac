import Foundation

// Fetches Canada Gazette notices from the official RSS feeds.
// Source: gazette.gc.ca — authoritative Government of Canada publication.
// No AI-generated content.

struct GazetteService {
    private enum Constants {
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    private static let partIURL  = URL(string: "https://gazette.gc.ca/rss/p1-eng.xml")!
    private static let partIIURL = URL(string: "https://gazette.gc.ca/rss/p2-eng.xml")!

    // MARK: - Public

    static func fetchAll() async throws -> [GazetteEntry] {
        async let partI  = fetch(url: partIURL, part: .partI)
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
        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, Constants.successStatusCodes.contains(http.statusCode) else {
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

    private static let itemTextFields: [String: ReferenceWritableKeyPath<GazetteRSSParser, String>] = [
        "title": \.currentTitle,
        "link": \.currentLink,
        "description": \.currentDescription,
        "pubDate": \.currentPubDate,
        "category": \.currentCategory
    ]

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
            resetCurrentItem()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        if let field = Self.itemTextFields[currentElement] {
            self[keyPath: field] += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard elementName == "item", inItem else { return }
        inItem = false

        if let entry = currentEntry() {
            entries.append(entry)
        }
    }

    private func resetCurrentItem() {
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        currentPubDate = ""
        currentCategory = ""
    }

    private func currentEntry() -> GazetteEntry? {
        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkStr = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let url = URL(string: linkStr) else { return nil }

        let date = rfc822Formatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .now
        let summary = currentDescription
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let category = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = linkStr

        return GazetteEntry(
            id: id,
            title: title,
            url: url,
            publicationDate: date,
            part: part,
            category: category,
            summary: summary
        )
    }
}
