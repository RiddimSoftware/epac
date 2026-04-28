import SwiftUI
import SwiftData

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifPrefs = NotificationPreferenceStore.shared
    @State private var billStore = BillFollowStore.shared
    @State private var memberStore = MemberFollowStore.shared
    @State private var topicStore = TopicFollowStore.shared
    @State private var selectedAppIcon = AppIconOption.current
    @State private var appIconError: String?
    @State private var showPostalCodeChange = false
    @Query private var members: [ParliamentMember]

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                locationSection
                notificationsSection
                appIconSection
                followedSection
                aboutSection
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

    // MARK: - Appearance

    private var appIconSection: some View {
        Section(NSLocalizedString("settings.appIcon.title", comment: "")) {
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

    // MARK: - My Location

    private var locationSection: some View {
        Section(NSLocalizedString("settings.location.title", comment: "")) {
            if let ridingName = PostalCodeViewModel.savedRidingName {
                LabeledContent(
                    NSLocalizedString("settings.location.riding", comment: ""),
                    value: ridingName
                )
            }
            if let memberName = PostalCodeViewModel.savedMemberName,
               memberName != PostalCodeViewModel.savedRidingName {
                LabeledContent(
                    NSLocalizedString("settings.location.mp", comment: ""),
                    value: memberName
                )
            }
            Button(NSLocalizedString("settings.location.change", comment: "")) {
                showPostalCodeChange = true
            }
            .foregroundStyle(.tint)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section(NSLocalizedString("settings.notifications.title", comment: "")) {
            NavigationLink(destination: NotificationSettingsView()) {
                Label(
                    NSLocalizedString("settings.notifications.manage", comment: ""),
                    systemImage: "bell.badge"
                )
            }
        }
    }

    // MARK: - Followed

    @ViewBuilder
    private var followedSection: some View {
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

    // MARK: - About

    private var aboutSection: some View {
        Section(NSLocalizedString("settings.about.title", comment: "")) {
            LabeledContent(NSLocalizedString("settings.about.version", comment: ""), value: appVersion)
            NavigationLink(NSLocalizedString("settings.about.privacy", comment: "")) {
                PrivacyPolicyView()
            }
            Link(
                NSLocalizedString("settings.about.dataSources", comment: ""),
                destination: URL(string: "https://epac.riddimsoftware.com/sources")!
            )
            Link(
                NSLocalizedString("settings.about.github", comment: ""),
                destination: URL(string: "https://github.com/sunnypurewal/epac")!
            )
            Link(
                NSLocalizedString("settings.about.brandBrief", comment: ""),
                destination: URL(string: "https://github.com/sunnypurewal/epac/blob/main/docs/brand/brand-brief-v1.md")!
            )
            Button(NSLocalizedString("settings.about.feedback", comment: "")) {
                let subject = "epac%20feedback"
                if let url = URL(string: "mailto:sunny@riddimsoftware.com?subject=\(subject)") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundStyle(.tint)
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
