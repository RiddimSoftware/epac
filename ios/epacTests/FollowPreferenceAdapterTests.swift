@testable import epac
import Foundation
import Testing

@MainActor
struct FollowPreferenceAdapterTests {
    
    init() {
        PostalCodeStore.shared.clear()
    }

    @Test func savedMemberNameReflectsPostalCodeStore() {
        let adapter = FollowPreferenceAdapter()
        let store = PostalCodeStore.shared
        
        #expect(adapter.savedMemberName() == nil)
        
        store.set(postalCode: "K1A 0A6", ridingName: "Ottawa Centre", memberName: "Yasir Naqvi")
        #expect(adapter.savedMemberName() == "Yasir Naqvi")
        
        store.clear()
        #expect(adapter.savedMemberName() == nil)
    }
}
