//
//  LEGISinfoBillRepository.swift
//  epac
//

import Foundation

@MainActor
struct LEGISinfoBillRepository: BillRepository {
    func fetchBills() async throws -> [Bill] {
        try await BillsService.fetchBills()
    }
}
