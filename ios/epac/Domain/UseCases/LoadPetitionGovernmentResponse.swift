//
//  LoadPetitionGovernmentResponse.swift
//  epac
//

import Foundation

@MainActor
struct LoadPetitionGovernmentResponse {
    private let queryPort: PetitionGovernmentResponseQueryPort

    init(queryPort: PetitionGovernmentResponseQueryPort) {
        self.queryPort = queryPort
    }

    func execute(petitionID: String) async throws -> PetitionGovernmentResponse? {
        try await queryPort.fetchGovernmentResponse(for: petitionID)
    }
}
