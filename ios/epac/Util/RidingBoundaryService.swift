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
	private let baseURL: URL
	private let network: NetworkService

	init(baseURL: URL = BackendConfig.shared.baseURL, network: NetworkService = .shared) {
		self.baseURL = baseURL
		self.network = network
	}

	func boundary(for ridingName: String) async throws -> RidingBoundary {
		let slug = Self.slug(for: ridingName)
		guard !slug.isEmpty else { throw RidingBoundaryServiceError.invalidURL }
		let url = baseURL
			.appendingPathComponent("api/v1/ridings")
			.appendingPathComponent(slug)
			.appendingPathComponent("boundary")
		let (data, response) = try await network.data(from: url)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw RidingBoundaryServiceError.invalidResponse
		}
		if httpResponse.statusCode == 404 {
			throw RidingBoundaryServiceError.notFound
		}
		guard (200..<300).contains(httpResponse.statusCode) else {
			throw RidingBoundaryServiceError.invalidResponse
		}
		return try JSONDecoder().decode(RidingBoundary.self, from: data)
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
