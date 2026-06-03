@testable import epac
import Foundation
import Network
import XCTest

final class NetworkBytesPerfTests: XCTestCase {
    func testNetworkBytesForHansardXMLRequest() throws {
        let fixtureData = try Data(contentsOf: hansardFixtureURL())
        XCTAssertFalse(fixtureData.isEmpty)

        let server = try LocalHTTPFixtureServer(responseBody: fixtureData)
        let baseURL = try server.start()
        defer { server.stop() }

        let metric = NetworkBytesMetric()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: metric, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let suiteName = "NetworkBytesPerfTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkBytesPerfTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: cacheDirectory)
        }

        let service = NetworkService(
            session: session,
            cacheStore: HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
        )
        var request = URLRequest(url: hansardRequestURL(relativeTo: baseURL))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let options = XCTMeasureOptions.default
        options.iterationCount = 3

        // EPAC-2209 will make Fetch.downloadHansard's network dependency injectable; until then this
        // measures the NetworkService / URLSession adapter boundary used by that full debate-load path.
        measure(metrics: [metric], options: options) {
            guard let result = Self.performRequest(service: service, request: request) else {
                XCTFail("Timed out waiting for Hansard XML request")
                return
            }

            do {
                let (data, response) = try result.get()
                XCTAssertEqual(data.count, fixtureData.count)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertTrue(metric.waitForCollectedTaskMetrics(), "URLSession did not deliver task metrics")
            } catch {
                XCTFail("Hansard XML request failed: \(error)")
            }
        }

        let reportedByteCounts = metric.reportedByteCounts
        XCTAssertFalse(reportedByteCounts.isEmpty, "EPAC-2200 presence guard: metric did not report byte counts")
        XCTAssertTrue(
            reportedByteCounts.allSatisfy { $0 > 0 },
            "EPAC-2200 presence guard: expected non-empty network byte measurements, got \(reportedByteCounts)"
        )

        let maxByteCount = try XCTUnwrap(reportedByteCounts.max())
        XCTAssertLessThanOrEqual(maxByteCount, try networkBytesBudget())
    }

    private static func performRequest(
        service: NetworkService,
        request: URLRequest
    ) -> Result<(Data, URLResponse), Error>? {
        let resultBox = AsyncResultBox<(Data, URLResponse)>()
        let completion = DispatchSemaphore(value: 0)

        Task {
            do {
                resultBox.set(.success(try await service.data(for: request)))
            } catch {
                resultBox.set(.failure(error))
            }
            completion.signal()
        }

        guard completion.wait(timeout: .now() + .seconds(5)) == .success else {
            return nil
        }
        return resultBox.value
    }

    private func hansardFixtureURL() -> URL {
        testsRootURL()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("45-1-HAN073-E.XML", isDirectory: false)
    }

    private func hansardRequestURL(relativeTo baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("content")
            .appendingPathComponent("hoc")
            .appendingPathComponent("House")
            .appendingPathComponent("451")
            .appendingPathComponent("Debates")
            .appendingPathComponent("073")
            .appendingPathComponent("HAN073-E.XML")
    }

    private func networkBytesBudget() throws -> Int64 {
        let rawBudget = try String(contentsOf: networkBytesBudgetURL(), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let budget = Int64(rawBudget), budget > 0 else {
            throw NetworkBytesPerfError.invalidBudget(rawBudget)
        }
        return budget
    }

    private func networkBytesBudgetURL() -> URL {
        repositoryRootURL()
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("perf-budgets", isDirectory: true)
            .appendingPathComponent("debate-load-network-bytes.sim.txt", isDirectory: false)
    }

    private func testsRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repositoryRootURL() -> URL {
        testsRootURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class AsyncResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Result<Value, Error>?

    var value: Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Result<Value, Error>) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private final class LocalHTTPFixtureServer: @unchecked Sendable {
    private enum Constants {
        static let loopbackHost = "127.0.0.1"
        static let minimumRequestBytes = 1
        static let maximumRequestBytes = 16_384
        static let startupTimeoutSeconds = 5
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "NetworkBytesPerfTests.LocalHTTPFixtureServer")

    init(responseBody: Data) throws {
        listener = try NWListener(using: .tcp, on: .any)

        let body = responseBody
        let serverQueue = queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: serverQueue)
            Self.respond(to: connection, body: body)
        }
    }

    func start(timeout: DispatchTimeInterval = .seconds(Constants.startupTimeoutSeconds)) throws -> URL {
        let startup = LocalHTTPFixtureServerStartup()
        listener.stateUpdateHandler = { [weak self, startup] state in
            guard let self else { return }
            switch state {
            case .ready:
                startup.succeed(port: self.listener.port)
            case .failed(let error):
                startup.fail(error)
            case .cancelled:
                startup.fail(NetworkBytesPerfError.serverCancelled)
            default:
                break
            }
        }

        listener.start(queue: queue)
        let port = try startup.wait(timeout: timeout)
        return URL(string: "http://\(Constants.loopbackHost):\(port.rawValue)/")!
    }

    func stop() {
        listener.cancel()
    }

    private static func respond(to connection: NWConnection, body: Data) {
        connection.receive(
            minimumIncompleteLength: Constants.minimumRequestBytes,
            maximumLength: Constants.maximumRequestBytes
        ) { _, _, _, error in
            guard error == nil else {
                connection.cancel()
                return
            }

            var response = Data(httpHeader(for: body).utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func httpHeader(for body: Data) -> String {
        "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/xml; charset=utf-8\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n"
    }
}

private final class LocalHTTPFixtureServerStartup: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<NWEndpoint.Port, Error>?

    func succeed(port: NWEndpoint.Port?) {
        guard let port else {
            complete(.failure(NetworkBytesPerfError.serverMissingPort))
            return
        }
        complete(.success(port))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    func wait(timeout: DispatchTimeInterval) throws -> NWEndpoint.Port {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw NetworkBytesPerfError.serverStartupTimedOut
        }

        lock.lock()
        let result = result
        lock.unlock()

        guard let result else {
            throw NetworkBytesPerfError.serverStartupTimedOut
        }
        return try result.get()
    }

    private func complete(_ newResult: Result<NWEndpoint.Port, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard result == nil else { return }
        result = newResult
        semaphore.signal()
    }
}

private enum NetworkBytesPerfError: Error {
    case invalidBudget(String)
    case serverCancelled
    case serverMissingPort
    case serverStartupTimedOut
}
