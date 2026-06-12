@testable import epac
import Foundation
import Testing

@MainActor
struct PostalCodeStoreTests {
    init() {
        // Clear keys before each test
        PostalCodeStore.shared.clear()
    }

    @Test func setUpdatesPropertiesAndUserDefaults() {
        let store = PostalCodeStore.shared

        store.set(postalCode: "K1A 0A6", ridingName: "Ottawa Centre", memberName: "Yasir Naqvi")

        #expect(store.savedPostalCode == "K1A 0A6")
        #expect(store.savedRidingName == "Ottawa Centre")
        #expect(store.savedMemberName == "Yasir Naqvi")

        let defaults = UserDefaults.standard
        #expect(defaults.string(forKey: "epac.myMP.postalCode") == "K1A 0A6")
        #expect(defaults.string(forKey: "epac.myMP.ridingName") == "Ottawa Centre")
        #expect(defaults.string(forKey: "epac.myMP.memberName") == "Yasir Naqvi")
    }

    @Test func setTrimsPostalCode() {
        let store = PostalCodeStore.shared

        store.set(postalCode: "  K1A 0A6  ", ridingName: "Ottawa Centre", memberName: "Yasir Naqvi")

        #expect(store.savedPostalCode == "K1A 0A6")
    }

    @Test func setUsesRidingNameIfMemberNameIsEmpty() {
        let store = PostalCodeStore.shared

        store.set(postalCode: "K1A 0A6", ridingName: "Ottawa Centre", memberName: "")

        #expect(store.savedMemberName == "Ottawa Centre")
        #expect(UserDefaults.standard.string(forKey: "epac.myMP.memberName") == "Ottawa Centre")
    }

    @Test func clearRemovesPropertiesAndUserDefaults() {
        let store = PostalCodeStore.shared
        store.set(postalCode: "K1A 0A6", ridingName: "Ottawa Centre", memberName: "Yasir Naqvi")

        store.clear()

        #expect(store.savedPostalCode == nil)
        #expect(store.savedRidingName == nil)
        #expect(store.savedMemberName == nil)

        let defaults = UserDefaults.standard
        #expect(defaults.string(forKey: "epac.myMP.postalCode") == nil)
        #expect(defaults.string(forKey: "epac.myMP.ridingName") == nil)
        #expect(defaults.string(forKey: "epac.myMP.memberName") == nil)
    }
}
