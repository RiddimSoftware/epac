//
//  LEGISinfoBillRepository.swift
//  epac
//

import Foundation

@MainActor
struct LEGISinfoBillRepository: BillRepository, BillStatusReadPort {
    func fetchBills() async throws -> [Bill] {
        try await BillsService.fetchBills()
    }
}

