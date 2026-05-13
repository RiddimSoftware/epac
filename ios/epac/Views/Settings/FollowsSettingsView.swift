import SwiftData
import SwiftUI

@MainActor
struct FollowsSettingsView: View {
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
                    for index in indexSet { billStore.unfollow(sorted[index].key) }
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
                        for index in indexSet { memberStore.unfollow(sorted[index].memberID) }
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
                    for index in indexSet { topicStore.unfollow(sorted[index].id) }
                }
            }
        }
    }
}
