//
//  LoadMPBiography.swift
//  epac
//

struct LoadMPBiography: Sendable {
	private let repository: any MPBiographyRepository

	init(repository: any MPBiographyRepository) {
		self.repository = repository
	}

	func execute(memberID: Int) async throws -> MemberBiography {
		try await repository.loadBiography(memberID: memberID)
	}
}
