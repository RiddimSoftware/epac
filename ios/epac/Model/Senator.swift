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
    let appointment: SenateAppointment?

    var caucusColor: Color {
        switch caucus.uppercased() {
        case "CPC", "CONS": return Color(UIColor.systemBlue)
        case "PSG":         return Color(UIColor.systemRed)
        case "ISG":         return Color(UIColor.systemTeal)
        case "CSG":         return Color(UIColor.systemPurple)
        default:            return Color(UIColor.systemGray)
        }
    }

    var appointmentDate: Date? {
        appointment?.date ?? appointedDate
    }

    var appointmentSourceURL: URL {
        appointment?.sourceURL ?? SenateAppointment.defaultSourceURL
    }
}

struct SenateAppointment: Codable, Equatable {
    static let defaultSourceURL = URL(string: "https://pco-bcp.gc.ca/oic-ddc")!

    let date: Date
    let appointingPrimeMinister: String?
    let province: String
    let declaredAffiliation: String
    let sourceURL: URL

    init(
        date: Date,
        appointingPrimeMinister: String?,
        province: String,
        declaredAffiliation: String,
        sourceURL: URL = Self.defaultSourceURL
    ) {
        self.date = date
        self.appointingPrimeMinister = appointingPrimeMinister
        self.province = province
        self.declaredAffiliation = declaredAffiliation
        self.sourceURL = sourceURL
    }
}
