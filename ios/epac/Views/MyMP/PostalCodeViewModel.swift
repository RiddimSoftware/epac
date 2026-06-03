import Observation
import SwiftData
import SwiftUI

struct RidingLookupResult {
    let memberName: String
    let ridingName: String
    let partyName: String
}

@MainActor
@Observable
class PostalCodeViewModel {
    var postalCode: String = ""
    var isLoading: Bool = false
    var result: RidingLookupResult?
    var errorMessage: String?

    private let memberRepository: any MemberRepository
    private let store = PostalCodeStore.shared
    private let telemetry: any TelemetryProvider

    init(
        memberRepository: any MemberRepository = RidingLookupMemberRepository(),
        telemetry: any TelemetryProvider = CurrentTelemetryProvider()
    ) {
        self.memberRepository = memberRepository
        self.telemetry = telemetry
    }

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
            let ridingName = try await memberRepository.lookupRiding(postalCode: trimmed)

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
            telemetry.recordError(error)
        }
    }

    static func currentMember(for ridingName: String, in members: [ParliamentMember]) -> ParliamentMember? {
        let normalized = RidingNameNormalizer.normalize(ridingName)
        return members
            .filter {
                $0.toDateTime == nil
                    && RidingNameNormalizer.normalize($0.riding) == normalized
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
