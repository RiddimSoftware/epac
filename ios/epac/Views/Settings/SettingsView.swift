import SwiftData
import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAppIcon = AppIconOption.current
    @State private var appIconError: String?
    @State private var showPostalCodeChange = false
    @State private var postalCodeStore = PostalCodeStore.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                languageSection
                notificationsSection
                followsSection
                dataPrivacySection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("settings.done", comment: "")) { dismiss() }
                }
            }
            .regularSizeClassFormSheet(isPresented: $showPostalCodeChange) {
                PostalCodeSetupView { showPostalCodeChange = false }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(NSLocalizedString("settings.account.title", comment: "")) {
            if let ridingName = postalCodeStore.savedRidingName {
                LabeledContent(
                    NSLocalizedString("settings.account.riding", comment: ""),
                    value: ridingName
                )
            }
            if let memberName = postalCodeStore.savedMemberName,
               memberName != postalCodeStore.savedRidingName {
                LabeledContent(
                    NSLocalizedString("settings.account.mp", comment: ""),
                    value: memberName
                )
            }
            Button {
                showPostalCodeChange = true
            } label: {
                Label(
                    NSLocalizedString("settings.account.postalCode", comment: ""),
                    systemImage: "mappin.and.ellipse"
                )
            }
            .foregroundStyle(.tint)

        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section(NSLocalizedString("settings.appearance.title", comment: "")) {
            LabeledContent(
                NSLocalizedString("settings.appearance.theme", comment: ""),
                value: NSLocalizedString("settings.appearance.theme.system", comment: "")
            )
            appIconRow
        }
    }

    @ViewBuilder
    private var appIconRow: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Picker(
                NSLocalizedString("settings.appIcon.picker", comment: ""),
                selection: $selectedAppIcon
            ) {
                ForEach(AppIconOption.allCases) { option in
                    Label(option.localizedTitle, systemImage: option.systemImageName)
                        .tag(option)
                }
            }
            .onChange(of: selectedAppIcon) { _, option in
                applyAppIcon(option)
            }

            if let appIconError {
                Text(appIconError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            LabeledContent(
                NSLocalizedString("settings.appIcon.picker", comment: ""),
                value: NSLocalizedString("settings.appIcon.unsupported", comment: "")
            )
        }
    }

    private func applyAppIcon(_ option: AppIconOption) {
        guard UIApplication.shared.alternateIconName != option.iconName else { return }

        UIApplication.shared.setAlternateIconName(option.iconName) { error in
            Task { @MainActor in
                if let error {
                    appIconError = String(
                        format: NSLocalizedString("settings.appIcon.error", comment: ""),
                        error.localizedDescription
                    )
                    selectedAppIcon = AppIconOption.current
                } else {
                    appIconError = nil
                }
            }
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section(NSLocalizedString("settings.language.title", comment: "")) {
            LabeledContent(
                NSLocalizedString("settings.language.preference", comment: ""),
                value: NSLocalizedString("settings.language.system", comment: "")
            )
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section(NSLocalizedString("settings.notifications.title", comment: "")) {
            NavigationLink(destination: NotificationsSettingsView()) {
                Label(
                    NSLocalizedString("settings.notifications.manage", comment: ""),
                    systemImage: "bell.badge"
                )
            }
        }
    }

    // MARK: - Follows

    private var followsSection: some View {
        Section(NSLocalizedString("settings.follows.title", comment: "")) {
            NavigationLink(destination: FollowsSettingsView()) {
                Label(
                    NSLocalizedString("settings.follows.manage", comment: ""),
                    systemImage: "star.circle"
                )
            }
        }
    }

    // MARK: - Data & Privacy

    private var dataPrivacySection: some View {
        Section(NSLocalizedString("settings.privacy.title", comment: "")) {
            NavigationLink(NSLocalizedString("settings.privacy.policy", comment: "")) {
                PrivacyPolicyView()
            }
            Link(
                NSLocalizedString("settings.privacy.dataHandling", comment: ""),
                destination: URL(string: "https://epac.riddimsoftware.com/privacy.html")!
            )
            Link(
                NSLocalizedString("settings.privacy.dataSources", comment: ""),
                destination: URL(string: "https://epac.riddimsoftware.com/sources")!
            )
            Button(NSLocalizedString("settings.privacy.export", comment: "")) {}
                .disabled(true)
            Button(NSLocalizedString("settings.privacy.delete", comment: ""), role: .destructive) {}
                .disabled(true)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(NSLocalizedString("settings.about.title", comment: "")) {
            LabeledContent(NSLocalizedString("settings.about.version", comment: ""), value: appVersion)
            Link(
                NSLocalizedString("settings.about.sourceCredits", comment: ""),
                destination: URL(string: "https://epac.riddimsoftware.com/sources")!
            )
            Link(
                NSLocalizedString("settings.about.github", comment: ""),
                destination: URL(string: "https://github.com/RiddimSoftware/epac")!
            )
            Link(
                NSLocalizedString("settings.about.brandBrief", comment: ""),
                destination: URL(
                    string: "https://github.com/RiddimSoftware/epac/blob/main/docs/brand/brand-brief-v1.md"
                )!
            )
            Button(NSLocalizedString("settings.about.feedback", comment: "")) {
                let subject = "epac%20feedback"
                if let url = URL(string: "mailto:epac@riddimsoftware.com?subject=\(subject)") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundStyle(.tint)
            Link(
                NSLocalizedString("settings.about.rate", comment: ""),
                destination: URL(string: "itms-apps://itunes.apple.com/app/id1224459142?action=write-review")!
            )
        }
    }

    // MARK: - Developer

    #if DEBUG
    private var developerSection: some View {
        Section(NSLocalizedString("settings.developer.title", comment: "")) {
            LabeledContent(
                NSLocalizedString("settings.developer.diagnostics", comment: ""),
                value: NSLocalizedString("settings.developer.debugOnly", comment: "")
            )
            LabeledContent(
                NSLocalizedString("settings.developer.flags", comment: ""),
                value: NSLocalizedString("settings.developer.debugOnly", comment: "")
            )
            Link(
                NSLocalizedString("settings.developer.evidence", comment: ""),
                destination: URL(string: "https://github.com/RiddimSoftware/epac/tree/main/docs/build-evidence")!
            )
        }
    }
    #endif
}

private enum AppIconOption: String, CaseIterable, Identifiable {
    case standard
    case red
    case gold

    var id: String { rawValue }

    var iconName: String? {
        switch self {
        case .standard:
            nil
        case .red:
            "AppIconRed"
        case .gold:
            "AppIconGold"
        }
    }

    var localizedTitle: String {
        switch self {
        case .standard:
            NSLocalizedString("settings.appIcon.standard", comment: "")
        case .red:
            NSLocalizedString("settings.appIcon.red", comment: "")
        case .gold:
            NSLocalizedString("settings.appIcon.gold", comment: "")
        }
    }

    var systemImageName: String {
        switch self {
        case .standard:
            "app"
        case .red:
            "app.fill"
        case .gold:
            "sparkles"
        }
    }

    @MainActor
    static var current: AppIconOption {
        switch UIApplication.shared.alternateIconName {
        case "AppIconRed":
            .red
        case "AppIconGold":
            .gold
        default:
            .standard
        }
    }
}
