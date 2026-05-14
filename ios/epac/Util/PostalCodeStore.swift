//
//  PostalCodeStore.swift
//  epac
//
//  Persists the user's postal code and resolved riding/MP name in UserDefaults.
//

import Foundation
import Observation

@MainActor
@Observable
final class PostalCodeStore {
    static let shared = PostalCodeStore()

    private let ridingNameKey = "epac.myMP.ridingName"
    private let memberNameKey = "epac.myMP.memberName"
    private let postalCodeKey = "epac.myMP.postalCode"

    private(set) var savedRidingName: String?
    private(set) var savedMemberName: String?
    private(set) var savedPostalCode: String?

    private init() {
        let defaults = UserDefaults.standard
        savedRidingName = defaults.string(forKey: ridingNameKey)
        savedMemberName = defaults.string(forKey: memberNameKey)
        savedPostalCode = defaults.string(forKey: postalCodeKey)
    }

    func set(postalCode: String, ridingName: String, memberName: String) {
        let defaults = UserDefaults.standard
        let trimmedPostalCode = postalCode.trimmingCharacters(in: .whitespaces)
        
        defaults.set(trimmedPostalCode, forKey: postalCodeKey)
        defaults.set(ridingName, forKey: ridingNameKey)
        
        // If no MP resolved yet, save the riding name as a placeholder so the
        // home feed shows something meaningful rather than the "Find Your MP" prompt.
        let finalMemberName = memberName.isEmpty ? ridingName : memberName
        defaults.set(finalMemberName, forKey: memberNameKey)
        
        savedPostalCode = trimmedPostalCode
        savedRidingName = ridingName
        savedMemberName = finalMemberName
    }

    func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: postalCodeKey)
        defaults.removeObject(forKey: ridingNameKey)
        defaults.removeObject(forKey: memberNameKey)
        
        savedPostalCode = nil
        savedRidingName = nil
        savedMemberName = nil
    }
}
