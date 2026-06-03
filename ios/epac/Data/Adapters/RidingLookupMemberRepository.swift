//
//  RidingLookupMemberRepository.swift
//  epac
//

import Foundation

@MainActor
struct RidingLookupMemberRepository: MemberRepository {
    private let service: RidingLookupService

    init(service: RidingLookupService = RidingLookupService()) {
        self.service = service
    }

    func lookupRiding(postalCode: String) async throws -> String {
        try await service.lookupRiding(postalCode: postalCode)
    }
}
