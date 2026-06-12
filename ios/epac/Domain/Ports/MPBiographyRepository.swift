//
//  MPBiographyRepository.swift
//  epac
//

@MainActor
protocol MPBiographyRepository: Sendable {
	func loadBiography(memberID: Int) async throws -> MemberBiography
}
