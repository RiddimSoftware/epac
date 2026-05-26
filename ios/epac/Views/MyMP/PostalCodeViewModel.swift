import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
class PostalCodeViewModel {
    var postalCode: String = ""
    var isLoading: Bool = false
    var result: RidingLookupResult?
    var errorMessage: String?

    private let service = RidingLookupService()
    private let store = PostalCodeStore.shared

    static var savedRidingName: String? { PostalCodeStore.shared.savedRidingName }
    static var savedMemberName: String? { PostalCodeStore.shared.savedMemberName }
    static var savedPostalCode: String? { PostalCodeStore.shared.savedPostalCode }

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
            let descriptor = FetchDescriptor<ParliamentMember>(
                sortBy: [SortDescriptor(\.fromDateTime, order: .reverse)]
            )
            let allMembers = (try? modelContext.fetch(descriptor)) ?? []
            let mp = Self.currentMember(for: ridingName, in: allMembers)

            result = RidingLookupResult(
                memberName: mp?.name ?? "",
                ridingName: ridingName,
                partyName: mp?.party.fullName ?? ""
            )
        } catch let error as RidingLookupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = NSLocalizedString("riding.error.networkError", comment: "")
            Telemetry.recordError(error)
        }
    }

    static func currentMember(for ridingName: String, in members: [ParliamentMember]) -> ParliamentMember? {
        let normalized = RidingLookupService.normalizeRidingName(ridingName)
        return members
            .filter {
                $0.toDateTime == nil
                    && RidingLookupService.normalizeRidingName($0.riding) == normalized
            }
            .sorted { lhs, rhs in
                switch (lhs.fromDateTime, rhs.fromDateTime) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name < rhs.name
                }
            }
            .first
    }

    func confirm() {
        guard let result else { return }
        store.set(
            postalCode: postalCode,
            ridingName: result.ridingName,
            memberName: result.memberName
        )
    }

    static func clear() {
        PostalCodeStore.shared.clear()
    }
}
