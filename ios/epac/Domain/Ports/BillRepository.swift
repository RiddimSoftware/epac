//
//  BillRepository.swift
//  epac
//

import Foundation

@MainActor
protocol BillRepository: Sendable {
    func fetchBills() async throws -> [Bill]
}
