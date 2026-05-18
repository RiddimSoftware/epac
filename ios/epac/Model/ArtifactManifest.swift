import Foundation

struct ArtifactKey: Codable, Equatable, Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
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
