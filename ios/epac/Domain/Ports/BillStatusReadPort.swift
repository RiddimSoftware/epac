//
//  BillStatusReadPort.swift
//  epac
//
//  Created on 2026-06-12.
//

import Foundation

@MainActor
protocol BillStatusReadPort: Sendable {
    func fetchBills() async throws -> [Bill]
}
