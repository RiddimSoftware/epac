import Foundation

private let onThisDayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/Toronto")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private let onThisDayArtifactDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/Toronto")
    formatter.dateFormat = "MM-dd"
    return formatter
}()

// OnThisDayKind and OnThisDayItem live in Domain/Entities/OnThisDayItem.swift

struct OnThisDayResponse: Decodable {
    let date: String
    let items: [OnThisDayItem]
}

enum OnThisDayServiceError: Error {
    case badURL
    case networkError(Error)
    case decodeError(Error)
}

struct OnThisDayService {
    private let artifacts: any ArtifactFetching

    init(artifacts: any ArtifactFetching = ArtifactService.shared) {
        self.artifacts = artifacts
    }

    func fetch(date: Date = Date(), limit: Int = 5) async throws -> [OnThisDayItem] {
        #if DEBUG
        if let fixture = Self.debugFixtureJSON(),
           let data = fixture.data(using: .utf8) {
            return try JSONDecoder().decode(OnThisDayResponse.self, from: data).items
        }
        #endif

        do {
            let response = try await artifacts.fetch(artifactKey(date: date), as: OnThisDayResponse.self)
            return Array(response.items.prefix(max(0, limit)))
        } catch let error as DecodingError {
            throw OnThisDayServiceError.decodeError(error)
        } catch {
            throw OnThisDayServiceError.networkError(error)
        }
    }

    func artifactKey(date: Date = Date()) -> ArtifactKey {
        .onThisDay(monthDay: onThisDayArtifactDateFormatter.string(from: date))
    }

    #if DEBUG
    private static func debugFixtureJSON() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--on-this-day-fixture-json"),
           arguments.indices.contains(arguments.index(after: index)) {
            return arguments[arguments.index(after: index)]
        }
        return ProcessInfo.processInfo.environment["EPAC_DEBUG_ON_THIS_DAY_FIXTURE_JSON"]
    }
    #endif
}

enum OnThisDayTelemetry {
    enum Event: String {
        case impression
        case tap
        case dismiss
    }

    static func record(_ event: Event, itemID: String? = nil, date: Date = Date()) {
        let day = onThisDayDateFormatter.string(from: date)
        let key = "epac.onThisDay.\(event.rawValue).\(day)"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        if let itemID {
            Log.info("home.onThisDay.\(event.rawValue) item=\(itemID)")
        } else {
            Log.info("home.onThisDay.\(event.rawValue)")
        }
    }
}
