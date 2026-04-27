//
//  epacShortcuts.swift
//  epac
//

import AppIntents

// Registers epac's App Intents with the system so they appear in Shortcuts
// and are suggestible by Siri. iOS auto-discovers AppIntent conformances
// without additional Info.plist entries; AppShortcutsProvider generates
// the suggested phrases.
struct epacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ParliamentTodayIntent(),
            phrases: [
                "Is Parliament sitting today in \(.applicationName)",
                "Is the House sitting in \(.applicationName)",
                "Parliament schedule in \(.applicationName)"
            ],
            shortTitle: "Parliament Today",
            systemImageName: "building.columns"
        )
        AppShortcut(
            intent: OpenMemberIntent(),
            phrases: [
                "Open an MP profile in \(.applicationName)",
                "Find a member of parliament in \(.applicationName)"
            ],
            shortTitle: "Open MP Profile",
            systemImageName: "person.fill"
        )
    }
}
