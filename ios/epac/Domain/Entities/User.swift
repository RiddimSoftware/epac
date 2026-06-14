//
//  User.swift
//  epac
//

import Foundation

public struct User: Sendable, Equatable {
    public var dailyDigestOptIn: Bool

    public init(dailyDigestOptIn: Bool) {
        self.dailyDigestOptIn = dailyDigestOptIn
    }
}
