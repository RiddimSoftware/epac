//
//  RidingBoundaryService.swift
//  epac
//

import Foundation

enum RidingBoundaryServiceError: Error {
	case invalidURL
	case invalidResponse
	case notFound
}

struct RidingBoundaryService {
	private let artifacts: any ArtifactFetching

	init(artifacts: any ArtifactFetching = ArtifactService.shared) {
		self.artifacts = artifacts
	}

	func boundary(for ridingName: String) async throws -> RidingBoundary {
		let slug = Self.slug(for: ridingName)
		guard !slug.isEmpty else { throw RidingBoundaryServiceError.invalidURL }
		do {
			return try await artifacts.fetch(.ridingBoundary(slug: slug), as: RidingBoundary.self)
		} catch ArtifactError.artifactNotFound {
			throw RidingBoundaryServiceError.notFound
		} catch ArtifactError.httpStatus(404, _) {
			throw RidingBoundaryServiceError.notFound
		} catch {
			throw RidingBoundaryServiceError.invalidResponse
		}
	}

	static func slug(for ridingName: String) -> String {
		let folded = ridingName
			.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_CA"))
			.replacingOccurrences(of: "—", with: "-")
			.replacingOccurrences(of: "–", with: "-")
			.replacingOccurrences(of: "‑", with: "-")
			.replacingOccurrences(of: "'", with: "")
			.replacingOccurrences(of: "’", with: "")
		let scalars = folded.unicodeScalars.map { scalar -> Character in
			if CharacterSet.alphanumerics.contains(scalar) {
				return Character(scalar)
			}
			return "-"
		}
		return String(scalars)
			.split(separator: "-")
			.joined(separator: "-")
			.lowercased()
	}
}
