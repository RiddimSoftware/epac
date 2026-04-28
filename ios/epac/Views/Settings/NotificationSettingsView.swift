import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct NotificationSettingsView: View {
    @State private var prefs = NotificationPreferenceStore.shared

    var body: some View {
        List {
            systemPermissionSection
            if prefs.systemAuthorizationStatus == .authorized || prefs.systemAuthorizationStatus == .provisional {
                activitySection
                digestsSection
                governmentUpdatesSection
                generalSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("settings.notifications.title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .task { await prefs.refreshSystemPermission() }
    }

    // MARK: - System permission

    private var systemPermissionSection: some View {
        Section {
            switch prefs.systemAuthorizationStatus {
            case .authorized, .provisional:
                Label {
                    Text(NSLocalizedString("notifications.permission.granted", comment: ""))
                        .foregroundStyle(Color.epacText.primary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.epacBrand.positive)
                }
                .accessibilityLabel(NSLocalizedString("notifications.permission.granted", comment: ""))

            case .denied:
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    Label {
                        Text(NSLocalizedString("notifications.permission.denied", comment: ""))
                            .foregroundStyle(Color.epacText.primary)
                    } icon: {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(Color.epacStatus.warning)
                    }
                    Text(NSLocalizedString("notifications.permission.deniedHint", comment: ""))
                        .font(.epacCaption)
                        .foregroundStyle(Color.epacText.secondary)
                    Button(NSLocalizedString("notifications.permission.openSettings", comment: "")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.epacSubheadline)
                    .foregroundStyle(Color.epacBrand.accent)
                }
                .padding(.vertical, EpacSpacing.xs)

            case .notDetermined:
                Button {
                    Task {
                        _ = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])
                        await prefs.refreshSystemPermission()
                        Log.info("notification.permission.requested")
                    }
                } label: {
                    Label(
                        NSLocalizedString("notifications.permission.enable", comment: ""),
                        systemImage: "bell.badge"
                    )
                    .foregroundStyle(Color.epacBrand.accent)
                }

            case .ephemeral:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        } header: {
            Text(NSLocalizedString("notifications.section.permission", comment: ""))
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        Section {
            Toggle(
                NSLocalizedString("notifications.category.mpVotes", comment: ""),
                isOn: $prefs.followedMPVotes
            )
            Toggle(
                NSLocalizedString("notifications.category.mpSpeeches", comment: ""),
                isOn: $prefs.followedMPSpeeches
            )
            Toggle(
                NSLocalizedString("notifications.category.billStatus", comment: ""),
                isOn: $prefs.followedBillStatusChanges
            )
            Toggle(
                NSLocalizedString("notifications.category.topicAlerts", comment: ""),
                isOn: $prefs.followedTopicAlerts
            )
        } header: {
            Text(NSLocalizedString("notifications.section.activity", comment: ""))
        } footer: {
            Text(NSLocalizedString("notifications.section.activity.footer", comment: ""))
                .font(.epacCaption)
        }
    }

    // MARK: - Digests

    private var digestsSection: some View {
        Section {
            Toggle(
                NSLocalizedString("notifications.category.dailyDigest", comment: ""),
                isOn: $prefs.dailyDigest
            )
            Toggle(
                NSLocalizedString("notifications.category.fridayDigest", comment: ""),
                isOn: $prefs.fridayWeeklyDigest
            )
        } header: {
            Text(NSLocalizedString("notifications.section.digests", comment: ""))
        } footer: {
            Text(NSLocalizedString("notifications.section.digests.footer", comment: ""))
                .font(.epacCaption)
        }
    }

    // MARK: - Government updates

    private var governmentUpdatesSection: some View {
        Section {
            Toggle(
                NSLocalizedString("notifications.category.hansardSittings", comment: ""),
                isOn: $prefs.newHansardSittings
            )
            Toggle(
                NSLocalizedString("notifications.category.pboCosting", comment: ""),
                isOn: $prefs.pboCosting
            )
            Toggle(
                NSLocalizedString("notifications.category.lobbyingAlerts", comment: ""),
                isOn: $prefs.lobbyingAlerts
            )
        } header: {
            Text(NSLocalizedString("notifications.section.governmentUpdates", comment: ""))
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Toggle(
                NSLocalizedString("notifications.category.appAnnouncements", comment: ""),
                isOn: $prefs.appAnnouncements
            )
        } header: {
            Text(NSLocalizedString("notifications.section.general", comment: ""))
        }
    }
}
