//
//  Senator.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Plain Codable value type — not a SwiftData model.
//  Senators are fetched from the Senate of Canada / OurCommons open API
//  and cached in UserDefaults for one week.
//

import Foundation
import SwiftUI
import UIKit

struct Senator: Identifiable, Codable {
    let id: String
    let firstName: String
    let lastName: String
    var name: String { "\(firstName) \(lastName)" }
    let province: String        // 2-letter abbreviation e.g. "ON"
    let caucus: String          // e.g. "ISG", "CSG", "CPC", "PSG"
    let caucusFullName: String  // e.g. "Independent Senators Group"
    let senateURL: URL          // link to Senate profile page
    let appointedDate: Date?

    var caucusColor: Color {
        switch caucus.uppercased() {
        case "CPC", "CONS": return Color(UIColor.systemBlue)
        case "PSG":         return Color(UIColor.systemRed)
        case "ISG":         return Color(UIColor.systemTeal)
        case "CSG":         return Color(UIColor.systemPurple)
        default:            return Color(UIColor.systemGray)
        }
    }
}
