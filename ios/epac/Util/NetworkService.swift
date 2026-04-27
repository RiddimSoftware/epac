// NetworkService.swift
// epac
//
// Wraps URLSession with exponential backoff: 3 retries at 1s, 2s, 4s delays.
// Only retries on transient network errors (connection lost, timeout, etc).
// HTTP error status codes are not retried — they indicate a server-side problem.

import Foundation

struct NetworkService {
    static let shared = NetworkService()

    private let session: URLSession
    // 1 initial attempt + 3 retries = 4 total attempts.
    private let maxAttempts = 4

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt - 1)) // 1s, 2s, 4s
                try await Task.sleep(for: .seconds(delay))
            }
            do {
                return try await session.data(for: request)
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
