//
//  TopicsView.swift
//  epac
//
//  Browse all 20 Parliamentary topics and follow / unfollow each one.
//  Followed topics trigger local notifications when new matching Hansard
//  subjects or bills are detected.
//

import SwiftUI

struct TopicsView: View {
    @State private var store = TopicFollowStore.shared

    var body: some View {
        List(ParliamentaryTopic.all) { topic in
            HStack {
                VStack(alignment: .leading) {
                    Text(topic.localizedName)
                        .font(.subheadline)
                    Text(topic.keywords.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        }
        .listStyle(.plain)
        .navigationTitle(NSLocalizedString("topics.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }
}
