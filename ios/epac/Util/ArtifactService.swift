//
//  ArtifactService.swift
//  epac
//

import Foundation
import Observation

protocol ArtifactFetching {
    func fetch<T: Decodable>(_ artifact: ArtifactKey, as: T.Type) async throws -> T
    func fetchManifest() async throws -> ArtifactManifest
}

struct FetchArtifact {
    private let artifacts: any ArtifactFetching

    init(artifacts: any ArtifactFetching = ArtifactService.shared) {
        self.artifacts = artifacts
    }

    func execute<T: Decodable>(_ artifact: ArtifactKey, as type: T.Type) async throws -> T {
        try await artifacts.fetch(artifact, as: type)
    }
}

struct ArtifactKey: Codable, Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty, "ArtifactKey cannot be empty")
        precondition(!trimmed.hasPrefix("/"), "ArtifactKey must be relative to the artifact root")
        precondition(!trimmed.contains(".."), "ArtifactKey cannot contain parent-directory traversal")
        self.rawValue = trimmed
    }

    init(stringLiteral value: String) {
        self.init(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("..") else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Artifact keys must be non-empty relative paths"
            )
        }
        self.rawValue = trimmed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }

    func url(relativeTo baseURL: URL) -> URL {
        rawValue
            .split(separator: "/")
            .reduce(baseURL) { url, component in
                url.appendingPathComponent(String(component), isDirectory: false)
            }
    }

    var cacheFilename: String {
        rawValue.addingPercentEncoding(withAllowedCharacters: Self.cacheFilenameAllowed) ?? rawValue
    }

    private static let cacheFilenameAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
}

struct ArtifactManifest: Decodable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let artifacts: [ArtifactManifestEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case artifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported artifact manifest schema_version \(schemaVersion)"
            )
        }
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        artifacts = try container.decode([ArtifactManifestEntry].self, forKey: .artifacts)
    }

    func entry(for key: ArtifactKey) -> ArtifactManifestEntry? {
        artifacts.first { $0.key == key }
    }
}

struct ArtifactManifestEntry: Decodable, Equatable, Sendable {
    let key: ArtifactKey
    let sizeBytes: Int
    let contentHashSHA256: String
    let etag: String
    let lastModified: Date
    let schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case key
        case sizeBytes = "size_bytes"
        case contentHashSHA256 = "content_hash_sha256"
        case etag
        case lastModified = "last_modified"
        case schemaVersion = "schema_version"
    }
}

enum ArtifactError: Error, Equatable, LocalizedError {
    case offlineAndNoCache(ArtifactKey)
    case artifactNotFound(ArtifactKey)
    case malformedManifest(String)
    case decodeFailed(ArtifactKey, String)
    case invalidResponse(String)
    case httpStatus(Int, ArtifactKey?)
    case cacheFailure(String)

    var errorDescription: String? {
        switch self {
        case .offlineAndNoCache(let key):
            return "Artifact \(key.rawValue) is unavailable offline and has no cached copy."
        case .artifactNotFound(let key):
            return "Artifact \(key.rawValue) is not listed in manifest.json."
        case .malformedManifest(let reason):
            return "Artifact manifest is malformed: \(reason)"
        case .decodeFailed(let key, let reason):
            return "Artifact \(key.rawValue) could not be decoded: \(reason)"
        case .invalidResponse(let reason):
            return "Artifact service received an invalid response: \(reason)"
        case .httpStatus(let statusCode, let key):
            if let key {
                return "Artifact \(key.rawValue) request failed with HTTP \(statusCode)."
            }
            return "Artifact manifest request failed with HTTP \(statusCode)."
        case .cacheFailure(let reason):
            return "Artifact cache failed: \(reason)"
        }
    }
}

enum ArtifactServiceWarning: Equatable, Sendable {
    case staleCacheFallback(ArtifactKey)
}

@Observable
final class ArtifactServiceWarnings: @unchecked Sendable {
    private(set) var latestWarning: ArtifactServiceWarning?

    func publish(_ warning: ArtifactServiceWarning) {
        latestWarning = warning
    }
}

struct ArtifactConfig {
    static let shared = ArtifactConfig()
    static let productionBaseURL = URL(string: "https://epac-assets.riddimsoftware.com")!

    let baseURL: URL

    init() {
        self.baseURL = Self.resolvedBaseURL(
            envValue: ProcessInfo.processInfo.environment["ARTIFACTS_BASE_URL"],
            plistValue: Bundle.main.object(forInfoDictionaryKey: "ArtifactsBaseURL") as? String
        )
    }

    init(envValue: String?, plistValue: String?) {
        self.baseURL = Self.resolvedBaseURL(envValue: envValue, plistValue: plistValue)
    }

    static func resolvedBaseURL(envValue: String?, plistValue: String?) -> URL {
        if let override = validURL(envValue) {
            return override
        }
        if let configured = validURL(plistValue) {
            return configured
        }
        return productionBaseURL
    }

    static func validURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              let url = URL(string: trimmed),
              url.scheme == "https" else { return nil }
        return url
    }
}

struct ArtifactHTTPResult: Sendable {
    let statusCode: Int
    let data: Data
    let etag: String?
}

protocol ArtifactHTTPFetching: Sendable {
    func get(_ url: URL, ifNoneMatch: String?) async throws -> ArtifactHTTPResult
}

protocol ManifestFetching: Sendable {
    func fetchManifest(from url: URL, ifNoneMatch: String?) async throws -> ArtifactHTTPResult
}

struct URLSessionArtifactStore: ArtifactHTTPFetching, ManifestFetching, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(_ url: URL, ifNoneMatch: String?) async throws -> ArtifactHTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArtifactError.invalidResponse("Expected HTTPURLResponse")
        }

        return ArtifactHTTPResult(
            statusCode: httpResponse.statusCode,
            data: data,
            etag: Self.headerValue("ETag", in: httpResponse)
        )
    }

    func fetchManifest(from url: URL, ifNoneMatch: String?) async throws -> ArtifactHTTPResult {
        try await get(url, ifNoneMatch: ifNoneMatch)
    }

    private static func headerValue(_ name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields
            where String(describing: key).caseInsensitiveCompare(name) == .orderedSame {
            return String(describing: value)
        }
        return nil
    }
}

struct CachedArtifact: Sendable {
    let data: Data
    let etag: String
}

struct CachedManifest: Sendable {
    let data: Data
    let etag: String?
    let fetchedAt: Date
}

protocol ArtifactStore: Sendable {
    func cachedArtifact(for key: ArtifactKey) throws -> CachedArtifact?
    func writeArtifact(_ data: Data, etag: String, for key: ArtifactKey) throws
    func cachedManifest() throws -> CachedManifest?
    func writeManifest(_ data: Data, etag: String?, fetchedAt: Date) throws
}

final class FileManagerArtifactStore: ArtifactStore, @unchecked Sendable {
    static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artifacts", isDirectory: true)
    }

    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        cacheDirectory: URL = FileManagerArtifactStore.defaultCacheDirectory,
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    func cachedArtifact(for key: ArtifactKey) throws -> CachedArtifact? {
        let bodyURL = artifactBodyURL(for: key)
        let metadataURL = artifactMetadataURL(for: key)
        guard fileManager.fileExists(atPath: bodyURL.path),
              fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: bodyURL)
            let metadata = try decoder.decode(
                CachedArtifactMetadata.self,
                from: Data(contentsOf: metadataURL)
            )
            return CachedArtifact(data: data, etag: metadata.etag)
        } catch {
            throw ArtifactError.cacheFailure(String(describing: error))
        }
    }

    func writeArtifact(_ data: Data, etag: String, for key: ArtifactKey) throws {
        do {
            try createCacheDirectoryIfNeeded()
            try atomicWrite(data, to: artifactBodyURL(for: key))
            let metadata = CachedArtifactMetadata(etag: etag)
            try atomicWrite(try encoder.encode(metadata), to: artifactMetadataURL(for: key))
        } catch {
            throw ArtifactError.cacheFailure(String(describing: error))
        }
    }

    func cachedManifest() throws -> CachedManifest? {
        guard fileManager.fileExists(atPath: manifestBodyURL.path),
              fileManager.fileExists(atPath: manifestMetadataURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: manifestBodyURL)
            let metadata = try decoder.decode(
                CachedManifestMetadata.self,
                from: Data(contentsOf: manifestMetadataURL)
            )
            return CachedManifest(data: data, etag: metadata.etag, fetchedAt: metadata.fetchedAt)
        } catch {
            throw ArtifactError.cacheFailure(String(describing: error))
        }
    }

    func writeManifest(_ data: Data, etag: String?, fetchedAt: Date) throws {
        do {
            try createCacheDirectoryIfNeeded()
            try atomicWrite(data, to: manifestBodyURL)
            let metadata = CachedManifestMetadata(etag: etag, fetchedAt: fetchedAt)
            try atomicWrite(try encoder.encode(metadata), to: manifestMetadataURL)
        } catch {
            throw ArtifactError.cacheFailure(String(describing: error))
        }
    }

    private var manifestBodyURL: URL {
        cacheDirectory.appendingPathComponent("manifest.json", isDirectory: false)
    }

    private var manifestMetadataURL: URL {
        cacheDirectory.appendingPathComponent("manifest.metadata.json", isDirectory: false)
    }

    private func artifactBodyURL(for key: ArtifactKey) -> URL {
        cacheDirectory.appendingPathComponent("\(key.cacheFilename).body", isDirectory: false)
    }

    private func artifactMetadataURL(for key: ArtifactKey) -> URL {
        cacheDirectory.appendingPathComponent("\(key.cacheFilename).metadata.json", isDirectory: false)
    }

    private func createCacheDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func atomicWrite(_ data: Data, to destinationURL: URL) throws {
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tempURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }
    }
}

private struct CachedArtifactMetadata: Codable {
    let etag: String
}

private struct CachedManifestMetadata: Codable {
    let etag: String?
    let fetchedAt: Date
}

final class ArtifactService: ArtifactFetching, @unchecked Sendable {
    static let shared = ArtifactService()

    let warnings: ArtifactServiceWarnings

    private let baseURL: URL
    private let artifactNetwork: any ArtifactHTTPFetching
    private let manifestNetwork: any ManifestFetching
    private let cacheStore: any ArtifactStore
    private let manifestTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let manifestCacheLock = NSLock()
    private var inMemoryManifest: CachedDecodedManifest?

    init(
        baseURL: URL = ArtifactConfig.shared.baseURL,
        artifactNetwork: any ArtifactHTTPFetching = URLSessionArtifactStore(),
        manifestNetwork: any ManifestFetching = URLSessionArtifactStore(),
        cacheStore: any ArtifactStore = FileManagerArtifactStore(),
        warnings: ArtifactServiceWarnings = ArtifactServiceWarnings(),
        manifestTTL: TimeInterval = 60 * 5,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.artifactNetwork = artifactNetwork
        self.manifestNetwork = manifestNetwork
        self.cacheStore = cacheStore
        self.warnings = warnings
        self.manifestTTL = manifestTTL
        self.now = now
    }

    func fetch<T: Decodable>(_ artifact: ArtifactKey, as type: T.Type) async throws -> T {
        let cached = try cacheStore.cachedArtifact(for: artifact)
        let manifest: ArtifactManifest

        do {
            manifest = try await fetchManifest()
        } catch {
            if shouldUseStaleFallback(for: error) {
                return try decodeStaleCachedArtifact(cached, artifact: artifact, as: type)
            }
            throw error
        }

        guard let manifestEntry = manifest.entry(for: artifact) else {
            throw ArtifactError.artifactNotFound(artifact)
        }

        if let cached,
           etagsMatch(cached.etag, manifestEntry.etag) {
            return try decode(cached.data, artifact: artifact, as: type)
        }

        do {
            let result = try await artifactNetwork.get(
                artifact.url(relativeTo: baseURL),
                ifNoneMatch: cached?.etag
            )
            return try handleArtifactResponse(
                result,
                artifact: artifact,
                manifestEntry: manifestEntry,
                cached: cached,
                as: type
            )
        } catch {
            if shouldUseStaleFallback(for: error) {
                return try decodeStaleCachedArtifact(cached, artifact: artifact, as: type)
            }
            throw error
        }
    }

    func fetchManifest() async throws -> ArtifactManifest {
        let fetchedAt = now()

        if let manifest = validInMemoryManifest(referenceDate: fetchedAt) {
            return manifest
        }

        let cachedManifest = try cacheStore.cachedManifest()
        if let cachedManifest,
           fetchedAt.timeIntervalSince(cachedManifest.fetchedAt) < manifestTTL {
            let manifest = try decodeManifest(cachedManifest.data)
            storeInMemoryManifest(CachedDecodedManifest(
                manifest: manifest,
                data: cachedManifest.data,
                etag: cachedManifest.etag,
                fetchedAt: cachedManifest.fetchedAt
            ))
            return manifest
        }

        let result = try await manifestNetwork.fetchManifest(
            from: baseURL.appendingPathComponent("manifest.json", isDirectory: false),
            ifNoneMatch: cachedManifest?.etag
        )

        switch result.statusCode {
        case 200:
            let manifest = try decodeManifest(result.data)
            try cacheStore.writeManifest(result.data, etag: result.etag, fetchedAt: fetchedAt)
            storeInMemoryManifest(CachedDecodedManifest(
                manifest: manifest,
                data: result.data,
                etag: result.etag,
                fetchedAt: fetchedAt
            ))
            return manifest
        case 304:
            guard let cachedManifest else {
                throw ArtifactError.invalidResponse("Manifest returned 304 without cached data")
            }
            let manifest = try decodeManifest(cachedManifest.data)
            try cacheStore.writeManifest(
                cachedManifest.data,
                etag: cachedManifest.etag,
                fetchedAt: fetchedAt
            )
            storeInMemoryManifest(CachedDecodedManifest(
                manifest: manifest,
                data: cachedManifest.data,
                etag: cachedManifest.etag,
                fetchedAt: fetchedAt
            ))
            return manifest
        default:
            throw ArtifactError.httpStatus(result.statusCode, nil)
        }
    }

    private func handleArtifactResponse<T: Decodable>(
        _ result: ArtifactHTTPResult,
        artifact: ArtifactKey,
        manifestEntry: ArtifactManifestEntry,
        cached: CachedArtifact?,
        as type: T.Type
    ) throws -> T {
        switch result.statusCode {
        case 200:
            let decoded = try decode(result.data, artifact: artifact, as: type)
            try cacheStore.writeArtifact(
                result.data,
                etag: result.etag ?? manifestEntry.etag,
                for: artifact
            )
            return decoded
        case 304:
            guard let cached else {
                throw ArtifactError.invalidResponse("Artifact \(artifact.rawValue) returned 304 without cached data")
            }
            return try decode(cached.data, artifact: artifact, as: type)
        default:
            throw ArtifactError.httpStatus(result.statusCode, artifact)
        }
    }

    private func decode<T: Decodable>(_ data: Data, artifact: ArtifactKey, as type: T.Type) throws -> T {
        do {
            return try Self.makeDecoder().decode(type, from: data)
        } catch {
            throw ArtifactError.decodeFailed(artifact, String(describing: error))
        }
    }

    private func decodeManifest(_ data: Data) throws -> ArtifactManifest {
        do {
            return try Self.makeDecoder().decode(ArtifactManifest.self, from: data)
        } catch {
            throw ArtifactError.malformedManifest(String(describing: error))
        }
    }

    private func decodeStaleCachedArtifact<T: Decodable>(
        _ cached: CachedArtifact?,
        artifact: ArtifactKey,
        as type: T.Type
    ) throws -> T {
        guard let cached else {
            throw ArtifactError.offlineAndNoCache(artifact)
        }
        warnings.publish(.staleCacheFallback(artifact))
        Log.warning("ArtifactService stale_cache_fallback artifact_key=\(artifact.rawValue)")
        return try decode(cached.data, artifact: artifact, as: type)
    }

    private func shouldUseStaleFallback(for error: Error) -> Bool {
        if error is URLError {
            return true
        }
        if case .httpStatus(let statusCode, _) = error as? ArtifactError {
            return (500..<600).contains(statusCode)
        }
        return false
    }

    private func validInMemoryManifest(referenceDate: Date) -> ArtifactManifest? {
        manifestCacheLock.lock()
        defer { manifestCacheLock.unlock() }
        guard let inMemoryManifest,
              referenceDate.timeIntervalSince(inMemoryManifest.fetchedAt) < manifestTTL else {
            return nil
        }
        return inMemoryManifest.manifest
    }

    private func storeInMemoryManifest(_ manifest: CachedDecodedManifest) {
        manifestCacheLock.lock()
        inMemoryManifest = manifest
        manifestCacheLock.unlock()
    }

    private func etagsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || strippedETag(lhs) == strippedETag(rhs)
    }

    private func strippedETag(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("W/") {
            trimmed.removeFirst(2)
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct CachedDecodedManifest: Sendable {
    let manifest: ArtifactManifest
    let data: Data
    let etag: String?
    let fetchedAt: Date
}
