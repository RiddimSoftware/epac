import Observation
import Sentry
import SwiftData
import SwiftUI

private let ridingNameKey = "epac.myMP.ridingName"
private let memberNameKey = "epac.myMP.memberName"
private let postalCodeKey = "epac.myMP.postalCode"

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
    static var savedPostalCode: String? { UserDefaults.standard.string(forKey: postalCodeKey) }

    func lookup(modelContext: ModelContext) async {
        let trimmed = postalCode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = nil
        defer { isLoading = false }
        do {
            let ridingName = try await service.lookupRiding(postalCode: trimmed)

            // Resolve MP from local SwiftData — stays on @MainActor, no data race.
            let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
            let normalized = RidingLookupService.normalizeRidingName(ridingName)
            let mp = allMembers.first {
                RidingLookupService.normalizeRidingName($0.riding) == normalized
            }

            result = RidingLookupResult(
                memberName: mp?.name ?? "",
                ridingName: ridingName,
                partyName: mp?.party.fullName ?? ""
            )
        } catch let error as RidingLookupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = NSLocalizedString("riding.error.networkError", comment: "")
            SentrySDK.capture(error: error)
        }
    }

    func confirm() {
        guard let result else { return }
        UserDefaults.standard.set(postalCode.trimmingCharacters(in: .whitespaces), forKey: postalCodeKey)
        UserDefaults.standard.set(result.ridingName, forKey: ridingNameKey)
        // If no MP resolved yet, save the riding name as a placeholder so the
        // home feed shows something meaningful rather than the "Find Your MP" prompt.
        UserDefaults.standard.set(result.memberName.isEmpty ? result.ridingName : result.memberName,
                                  forKey: memberNameKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: postalCodeKey)
        UserDefaults.standard.removeObject(forKey: ridingNameKey)
        UserDefaults.standard.removeObject(forKey: memberNameKey)
    }
}
