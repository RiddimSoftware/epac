//
//  PetitionGovernmentResponseQueryPort.swift
//  epac
//

import Foundation

@MainActor
protocol PetitionGovernmentResponseQueryPort: Sendable {
    func fetchGovernmentResponse(for petitionID: String) async throws -> PetitionGovernmentResponse?
}
