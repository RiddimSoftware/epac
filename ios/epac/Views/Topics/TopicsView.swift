//
//  TopicsView.swift
//  epac
//

import SwiftUI

struct TopicsView: View {
    @State private var store = TopicFollowStore.shared
    @State private var searchText = ""

    private var filtered: [ParliamentaryTopic] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return ParliamentaryTopic.all }
        return ParliamentaryTopic.all.filter {
            $0.localizedName.localizedCaseInsensitiveContains(q) ||
            $0.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        List(filtered) { topic in
            HStack {
                if topic.id == "transport" {
                    NavigationLink(destination: TransportationSafetyView()) {
                        topicSummary(topic)
                    }
                } else {
                    topicSummary(topic)
                }
                Spacer()
                Button {
                    store.toggle(topic.id)
                } label: {
                    Image(systemName: store.isFollowing(topic.id) ? "bell.fill" : "bell")
                        .foregroundStyle(store.isFollowing(topic.id) ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isFollowing(topic.id)
                    ? NSLocalizedString("topic.unfollow", comment: "")
                    : NSLocalizedString("topic.follow", comment: ""))
            }
            .padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if store.isFollowing(topic.id) {
                    Button(role: .destructive) {
                        store.unfollow(topic.id)
                    } label: {
                        Label(NSLocalizedString("topic.unfollow", comment: ""), systemImage: "bell.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: NSLocalizedString("topics.search.prompt", comment: "")
        )
        .navigationTitle(NSLocalizedString("topics.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }

    private func topicSummary(_ topic: ParliamentaryTopic) -> some View {
        VStack(alignment: .leading) {
            Text(topic.localizedName)
                .font(.subheadline)
            Text(topic.keywords.prefix(3).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
