@testable import epac
import Foundation

final class MockArtifactFetcher: ArtifactFetching, @unchecked Sendable {
    private let payloads: [ArtifactKey: Data]
    private let lock = NSLock()
    private var requests: [ArtifactKey] = []

    var requestedKeys: [ArtifactKey] {
        lock.withLock { requests }
    }

    init(_ payloads: [ArtifactKey: String]) {
        self.payloads = payloads.mapValues { Data($0.utf8) }
    }

    func fetch<T: Decodable>(_ artifact: ArtifactKey, as type: T.Type) async throws -> T {
        lock.withLock {
            requests.append(artifact)
        }
        guard let data = payloads[artifact] else {
            throw ArtifactError.artifactNotFound(artifact)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func fetchManifest() async throws -> ArtifactManifest {
        throw ArtifactError.malformedManifest("MockArtifactFetcher does not serve manifest.json")
    }
}
