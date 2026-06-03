//
//  RidingNameNormalizer.swift
//  epac
//

import Foundation

enum RidingNameNormalizer {
    static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .folding(options: .diacriticInsensitive, locale: nil)
    }
}
