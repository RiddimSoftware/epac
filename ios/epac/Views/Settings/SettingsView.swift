import SwiftData
import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAppIcon = AppIconOption.current
    @State private var appIconError: String?
    @State private var showPostalCodeChange = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                languageSection
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
            .sheet(isPresented: $showPostalCodeChange) {
                PostalCodeSetupView { showPostalCodeChange = false }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(NSLocalizedString("settings.account.title", comment: "")) {
            if let ridingName = PostalCodeViewModel.savedRidingName {
                LabeledContent(
                    NSLocalizedString("settings.account.riding", comment: ""),
                    value: ridingName
                )
            }
            if let memberName = PostalCodeViewModel.savedMemberName,
               memberName != PostalCodeViewModel.savedRidingName {
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

            NavigationLink(destination: NotificationSettingsView()) {
                Label(
                    NSLocalizedString("settings.account.notifications", comment: ""),
                    systemImage: "bell.badge"
                )
            }
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
                destination: URL(string: "https://github.com/RiddimSoftware/epac/blob/main/docs/brand/brand-brief-v1.md")!
            )
            Button(NSLocalizedString("settings.about.feedback", comment: "")) {
                let subject = "epac%20feedback"
                if let url = URL(string: "mailto:sunny@riddimsoftware.com?subject=\(subject)") {
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

@MainActor
private struct FollowsSettingsView: View {
    @State private var billStore = BillFollowStore.shared
    @State private var memberStore = MemberFollowStore.shared
    @State private var topicStore = TopicFollowStore.shared
    @Query private var members: [ParliamentMember]

    var body: some View {
        List {
            followedBillsSection
            followedMembersSection
            followedTopicsSection
            if billStore.followed.isEmpty,
               memberStore.followedIDs.isEmpty,
               topicStore.followedIDs.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("settings.follows.empty.title", comment: ""),
                    systemImage: "star",
                    description: Text(NSLocalizedString("settings.follows.empty.message", comment: ""))
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("settings.follows.title", comment: ""))
    }

    @ViewBuilder
    private var followedBillsSection: some View {
        if !billStore.followed.isEmpty {
            Section(NSLocalizedString("settings.followed.bills", comment: "")) {
                ForEach(
                    billStore.followed.sorted { $0.value.followedAt > $1.value.followedAt },
                    id: \.key
                ) { number, state in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(number)
                            .font(.subheadline.weight(.semibold))
                        Text(state.lastKnownStage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
                .onDelete { indexSet in
                    let sorted = billStore.followed.sorted { $0.value.followedAt > $1.value.followedAt }
                    for i in indexSet { billStore.unfollow(sorted[i].key) }
                }
            }
        }
    }

    @ViewBuilder
    private var followedMembersSection: some View {
        if !memberStore.followedIDs.isEmpty {
            let followedMembers = members
                .filter { memberStore.isFollowing($0.memberID) }
                .sorted { $0.name < $1.name }
            if !followedMembers.isEmpty {
                Section(NSLocalizedString("settings.followed.members", comment: "")) {
                    ForEach(followedMembers) { member in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.subheadline.weight(.semibold))
                            Text(member.party.fullName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        let sorted = members
                            .filter { memberStore.isFollowing($0.memberID) }
                            .sorted { $0.name < $1.name }
                        for i in indexSet { memberStore.unfollow(sorted[i].memberID) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var followedTopicsSection: some View {
        if !topicStore.followedIDs.isEmpty {
            let followedTopics = ParliamentaryTopic.all
                .filter { topicStore.isFollowing($0.id) }
                .sorted { $0.localizedName < $1.localizedName }
            Section(NSLocalizedString("settings.followed.topics", comment: "")) {
                ForEach(followedTopics) { topic in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.localizedName)
                            .font(.subheadline)
                        Picker("", selection: Binding(
                            get: { topicStore.granularity(for: topic.id) },
                            set: { topicStore.setGranularity($0, for: topic.id) }
                        )) {
                            Text("Every debate").tag(TopicNotificationGranularity.everyDebate)
                            Text("Only my MP").tag(TopicNotificationGranularity.onlyMyMP)
                            Text("Off").tag(TopicNotificationGranularity.off)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    let sorted = ParliamentaryTopic.all
                        .filter { topicStore.isFollowing($0.id) }
                        .sorted { $0.localizedName < $1.localizedName }
                    for i in indexSet { topicStore.unfollow(sorted[i].id) }
                }
            }
        }
    }
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
