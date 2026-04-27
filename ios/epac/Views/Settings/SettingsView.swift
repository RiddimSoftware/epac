import SwiftUI
import SwiftData
import UIKit

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifPrefs = NotificationPreferenceStore.shared
    @State private var billStore = BillFollowStore.shared
    @State private var memberStore = MemberFollowStore.shared
    @State private var topicStore = TopicFollowStore.shared
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
            Toggle(
                NSLocalizedString("settings.notifications.hansard", comment: ""),
                isOn: Binding(
                    get: { notifPrefs.newHansardSittings },
                    set: { notifPrefs.newHansardSittings = $0 }
                )
            )
            Toggle(
                NSLocalizedString("settings.notifications.billVotes", comment: ""),
                isOn: Binding(
                    get: { notifPrefs.billVoteResults },
                    set: { notifPrefs.billVoteResults = $0 }
                )
            )
            Toggle(
                NSLocalizedString("settings.notifications.memberActivity", comment: ""),
                isOn: Binding(
                    get: { notifPrefs.memberActivity },
                    set: { notifPrefs.memberActivity = $0 }
                )
            )
            Toggle(
                NSLocalizedString("settings.notifications.topicConsultations", comment: ""),
                isOn: Binding(
                    get: { notifPrefs.topicConsultations },
                    set: { notifPrefs.topicConsultations = $0 }
                )
            )
            Toggle(
                NSLocalizedString("settings.notifications.morningBriefing", comment: ""),
                isOn: Binding(
                    get: { notifPrefs.morningBriefing },
                    set: { notifPrefs.morningBriefing = $0 }
                )
            )
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
            Link(
                NSLocalizedString("settings.about.privacy", comment: ""),
                destination: URL(string: "https://epac.riddimsoftware.com/privacy")!
            )
            Link(
                NSLocalizedString("settings.about.dataSources", comment: ""),
                destination: URL(string: "https://epac.riddimsoftware.com/sources")!
            )
            Link(
                NSLocalizedString("settings.about.github", comment: ""),
                destination: URL(string: "https://github.com/sunnypurewal/epac")!
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
