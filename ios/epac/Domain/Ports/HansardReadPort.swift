//
//  HansardReadPort.swift
//  epac
//

import Foundation

@MainActor
public protocol HansardReadPort: Sendable {
    func fetchSubjectsCount(for date: Date) async throws -> Int
    func fetchTopSubjects(for date: Date, limit: Int) async throws -> [String]
    func isSittingDay(_ date: Date) async throws -> Bool
}
