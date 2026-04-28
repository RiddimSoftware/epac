// NetworkService.swift
// epac
//
// Wraps URLSession with exponential backoff: 3 retries at 1s, 2s, 4s delays.
// Only retries on transient network errors (connection lost, timeout, etc).
// HTTP error status codes are not retried — they indicate a server-side problem.

import Foundation

struct NetworkService: @unchecked Sendable {
    static let shared = NetworkService()

    private let session: URLSession
    private let cacheStore: HTTPResponseCacheStore
    // 1 initial attempt + 3 retries = 4 total attempts.
    private let maxAttempts = 4

    init(session: URLSession = .shared, cacheStore: HTTPResponseCacheStore = .shared) {
        self.session = session
        self.cacheStore = cacheStore
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let cachedRequest = cacheStore.prepare(request: request)
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt - 1)) // 1s, 2s, 4s
                try await Task.sleep(for: .seconds(delay))
            }
            do {
                let (data, response) = try await session.data(for: cachedRequest.request)
                return cacheStore.handle(data: data, response: response, for: cachedRequest)
            } catch let error as URLError {
                guard isTransient(error) else { throw error }
                lastError = error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }

    private func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dataNotAllowed,
             .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}

struct CachedHTTPRequest {
    let request: URLRequest
    let url: URL?
    let mayStoreResponse: Bool
    let mayServeStoredResponse: Bool
}

final class HTTPResponseCacheStore: @unchecked Sendable {
    static let shared = HTTPResponseCacheStore()

    private let userDefaults: UserDefaults
    private let cacheDirectory: URL
    private let fileManager: FileManager

    init(
        userDefaults: UserDefaults = .standard,
        cacheDirectory: URL = HTTPResponseCacheStore.defaultCacheDirectory,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    func prepare(request: URLRequest) -> CachedHTTPRequest {
        guard isCacheable(request), let url = request.url else {
            return CachedHTTPRequest(
                request: request,
                url: request.url,
                mayStoreResponse: false,
                mayServeStoredResponse: false
            )
        }

        let key = cacheKey(for: url)
        let etag = userDefaults.string(forKey: defaultsKey("etag", cacheKey: key))
        let lastModified = userDefaults.string(forKey: defaultsKey("lastModified", cacheKey: key))
        var conditionalRequest = request
        var didApplyValidator = false

        if hasCachedBody(cacheKey: key) {
            if conditionalRequest.value(forHTTPHeaderField: "If-None-Match") == nil,
               let etag,
               !etag.isEmpty {
                conditionalRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
                didApplyValidator = true
            } else if conditionalRequest.value(forHTTPHeaderField: "If-Modified-Since") == nil,
                      let lastModified,
                      !lastModified.isEmpty {
                conditionalRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                didApplyValidator = true
            }
        }

        return CachedHTTPRequest(
            request: conditionalRequest,
            url: url,
            mayStoreResponse: true,
            mayServeStoredResponse: didApplyValidator
        )
    }

    func handle(data: Data, response: URLResponse, for cachedRequest: CachedHTTPRequest) -> (Data, URLResponse) {
        guard cachedRequest.mayStoreResponse,
              let url = cachedRequest.url,
              let httpResponse = response as? HTTPURLResponse else {
            return (data, response)
        }

        if httpResponse.statusCode == 304,
           cachedRequest.mayServeStoredResponse,
           let cachedData = cachedData(for: url) {
            refreshValidators(from: httpResponse, for: url)
            return (cachedData, revalidatedResponse(from: httpResponse, url: url))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            return (data, response)
        }

        guard !isNoStore(response: httpResponse),
              hasValidator(response: httpResponse) else {
            removeCachedResponse(for: url)
            return (data, response)
        }

        store(data: data, response: httpResponse, for: url)
        return (data, response)
    }

    func removeCachedResponse(for url: URL) {
        let key = cacheKey(for: url)
        userDefaults.removeObject(forKey: defaultsKey("etag", cacheKey: key))
        userDefaults.removeObject(forKey: defaultsKey("lastModified", cacheKey: key))
        try? fileManager.removeItem(at: bodyURL(cacheKey: key))
    }

    private static var defaultCacheDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDirectory.appendingPathComponent("HTTPResponseCache", isDirectory: true)
    }

    private func store(data: Data, response: HTTPURLResponse, for url: URL) {
        let key = cacheKey(for: url)
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: bodyURL(cacheKey: key), options: [.atomic])
            replaceValidators(from: response, for: url)
        } catch {
            return
        }
    }

    private func hasCachedBody(cacheKey: String) -> Bool {
        fileManager.fileExists(atPath: bodyURL(cacheKey: cacheKey).path)
    }

    private func cachedData(for url: URL) -> Data? {
        try? Data(contentsOf: bodyURL(cacheKey: cacheKey(for: url)))
    }

    private func replaceValidators(from response: HTTPURLResponse, for url: URL) {
        let key = cacheKey(for: url)
        if let etag = headerValue("ETag", in: response) {
            userDefaults.set(etag, forKey: defaultsKey("etag", cacheKey: key))
        } else {
            userDefaults.removeObject(forKey: defaultsKey("etag", cacheKey: key))
        }
        if let lastModified = headerValue("Last-Modified", in: response) {
            userDefaults.set(lastModified, forKey: defaultsKey("lastModified", cacheKey: key))
        } else {
            userDefaults.removeObject(forKey: defaultsKey("lastModified", cacheKey: key))
        }
    }

    private func refreshValidators(from response: HTTPURLResponse, for url: URL) {
        let key = cacheKey(for: url)
        if let etag = headerValue("ETag", in: response) {
            userDefaults.set(etag, forKey: defaultsKey("etag", cacheKey: key))
        }
        if let lastModified = headerValue("Last-Modified", in: response) {
            userDefaults.set(lastModified, forKey: defaultsKey("lastModified", cacheKey: key))
        }
    }

    private func revalidatedResponse(from response: HTTPURLResponse, url: URL) -> HTTPURLResponse {
        HTTPURLResponse(
            url: response.url ?? url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: stringHeaders(from: response)
        ) ?? response
    }

    private func isCacheable(_ request: URLRequest) -> Bool {
        let method = (request.httpMethod ?? "GET").uppercased()
        return method == "GET"
    }

    private func isNoStore(response: HTTPURLResponse) -> Bool {
        guard let cacheControl = headerValue("Cache-Control", in: response)?.lowercased() else {
            return false
        }
        return cacheControl
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains("no-store")
    }

    private func hasValidator(response: HTTPURLResponse) -> Bool {
        headerValue("ETag", in: response) != nil || headerValue("Last-Modified", in: response) != nil
    }

    private func headerValue(_ name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields where String(describing: key).caseInsensitiveCompare(name) == .orderedSame {
            return String(describing: value)
        }
        return nil
    }

    private func stringHeaders(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { headers, field in
            headers[String(describing: field.key)] = String(describing: field.value)
        }
    }

    private func bodyURL(cacheKey: String) -> URL {
        cacheDirectory.appendingPathComponent("\(cacheKey).body", isDirectory: false)
    }

    private func defaultsKey(_ name: String, cacheKey: String) -> String {
        "NetworkService.HTTPResponseCache.\(cacheKey).\(name)"
    }

    private func cacheKey(for url: URL) -> String {
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
