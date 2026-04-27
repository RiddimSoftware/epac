//
//  OntarioLegislature.swift
//  epac
//
//  Plain Codable value types for Ontario Legislative Assembly data.
//  Not SwiftData models — cached in UserDefaults like Senator.
//

import Foundation

struct OntarioMPP: Identifiable, Codable {
    let id: String
    let firstName: String
    let lastName: String
    var name: String { "\(firstName) \(lastName)" }
    let party: String       // "PC", "NDP", "Liberal", "Green", "Independent"
    let riding: String      // Ontario riding name
    let email: String?
    let profileURL: URL
}

struct OntarioDebateDay: Identifiable, Codable {
    let id: String          // date string or slug
    let date: Date?
    let title: String       // "Debates and Proceedings"
    let parliament: Int     // 43
    let session: Int        // 1
    let publicationURL: URL // link to ola.org transcript
}
