//
//  MemberRepository.swift
//  epac
//

import Foundation

@MainActor
protocol MemberRepository: Sendable {
    func lookupRiding(postalCode: String) async throws -> String
}

enum RidingLookupError: LocalizedError, Equatable {
    case invalidPostalCode
    case networkError
    case noFederalRepresentative
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidPostalCode:
            return NSLocalizedString("riding.error.invalidPostalCode", comment: "")
        case .networkError:
            return NSLocalizedString("riding.error.networkError", comment: "")
        case .noFederalRepresentative:
            return NSLocalizedString("riding.error.noFederalRepresentative", comment: "")
        case .noResults:
            return NSLocalizedString("riding.error.noResults", comment: "")
        }
    }
}
