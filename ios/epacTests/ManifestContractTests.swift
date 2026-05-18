@testable import epac
import Foundation
import Testing

struct ManifestContractTests {
    @Test func backendManifestContractSampleDecodesAsArtifactManifest() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sampleURL = repoRoot.appendingPathComponent("backend/manifest/testdata/manifest.sample.json")
        let data = try Data(contentsOf: sampleURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest = try decoder.decode(ArtifactManifest.self, from: data)

        #expect(manifest.schemaVersion == ArtifactManifest.supportedSchemaVersion)
        #expect(manifest.generatedAt == Date(timeIntervalSince1970: 1_779_019_200))
        #expect(manifest.artifacts.map(\.key.rawValue) == ["members/v1/all.json", "sittings/v1/all.json"])
        #expect(manifest.artifacts[0].contentHashSHA256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
