//
//  NotificationsSettingsView.swift
//  epac
//

import SwiftUI

struct NotificationsSettingsView: View {
    @AppStorage("epac.notifications.dailyDigestEnabled") private var dailyDigestEnabled = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $dailyDigestEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.notifications.dailyDigest", comment: ""))
                            .font(.epacBody.weight(.medium))
                    }
                }
                .tint(Color.epacBrand.accent)
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
