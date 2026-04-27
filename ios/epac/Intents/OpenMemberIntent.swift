//
//  OpenMemberIntent.swift
//  epac
//

import AppIntents

// "Show me Jagmeet Singh in epac" — opens the Members tab and deep-links to a profile.
//
// Navigation handshake:
//   1. Intent writes pending memberID to UserDefaults["pendingMemberID"]
//   2. ContentView reads it on scenePhase.active and navigates
//   3. ContentView clears it after navigation
struct OpenMemberIntent: AppIntent {
    static let title: LocalizedStringResource = "Open MP Profile"
    static let description = IntentDescription(
        "Opens a Member of Parliament's profile in epac.",
        categoryName: "Members"
    )
    static let openAppWhenRun = true

    @Parameter(title: "MP Name", description: "The name of the Member of Parliament.")
    var memberName: String

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let query = memberName.lowercased().trimmingCharacters(in: .whitespaces)
        if let match = MemberNameCache.shared.find(query: query) {
            UserDefaults.standard.set(match.memberID, forKey: "pendingMemberID")
            return .result(dialog: "Opening \(match.name)'s profile.")
        }
        return .result(dialog: "I couldn't find an MP named \(memberName). Try opening epac and syncing data first.")
    }
}

// Notification name used by ContentView to trigger navigation after intent fires.
extension Notification.Name {
    static let openMemberByID = Notification.Name("net.dinglebox.cabinetdoor.openMemberByID")
}

// Lightweight in-memory index of member names, populated at app launch.
// Uses only primitive types (Int, String) so it can be used from AppIntent
// without referencing SwiftData @Model classes.
final class MemberNameCache: @unchecked Sendable {
    static let shared = MemberNameCache()

    struct Entry: Sendable {
        let memberID: Int
        let name: String
        let lastName: String
    }

    private var entries: [Entry] = []

    func populate(entries: [Entry]) {
        self.entries = entries
    }

    func find(query: String) -> (memberID: Int, name: String)? {
        if let exact = entries.first(where: { $0.lastName.lowercased() == query }) {
            return (exact.memberID, exact.name)
        }
        if let partial = entries.first(where: { $0.name.lowercased().contains(query) }) {
            return (partial.memberID, partial.name)
        }
        return nil
    }

    private init() {}
}
