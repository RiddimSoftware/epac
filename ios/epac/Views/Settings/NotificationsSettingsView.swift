//
//  NotificationsSettingsView.swift
//  epac
//

import SwiftUI

@MainActor
struct NotificationsSettingsView: View {
    @AppStorage(UserPreferenceAdapter.dailyDigestEnabledKey)
    private var dailyDigestEnabled = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $dailyDigestEnabled) {
                    Text(NSLocalizedString("settings.notifications.dailyDigest", comment: ""))
                        .font(.epacBody.weight(.medium))
                }
                .tint(Color.epacBrand.accent)
                .accessibilityIdentifier("settings.notifications.dailyDigest.toggle")
            } footer: {
                Text(NSLocalizedString("settings.notifications.dailyDigest.description", comment: ""))
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("settings.notifications.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
