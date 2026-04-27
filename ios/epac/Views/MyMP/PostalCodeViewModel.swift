import Observation
import SwiftUI

private let ridingNameKey = "epac.myMP.ridingName"
private let memberNameKey = "epac.myMP.memberName"

@MainActor
@Observable
class PostalCodeViewModel {
    var postalCode: String = ""
    var isLoading: Bool = false
    var result: RidingLookupResult?
    var errorMessage: String?

    private let service = RidingLookupService()

    static var savedRidingName: String? { UserDefaults.standard.string(forKey: ridingNameKey) }
    static var savedMemberName: String? { UserDefaults.standard.string(forKey: memberNameKey) }

    func lookup() async {
        let trimmed = postalCode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = nil
        defer { isLoading = false }
        do {
            result = try await service.lookup(postalCode: trimmed)
        } catch let error as RidingLookupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirm() {
        guard let result else { return }
        UserDefaults.standard.set(result.ridingName, forKey: ridingNameKey)
        UserDefaults.standard.set(result.memberName, forKey: memberNameKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: ridingNameKey)
        UserDefaults.standard.removeObject(forKey: memberNameKey)
    }
}
