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
            VStack(alignment: .leading, spacing: 8) {
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
                        Image(systemName: store.isFollowing(topic.id) ? "star.fill" : "star")
                            .foregroundStyle(store.isFollowing(topic.id) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.isFollowing(topic.id)
                        ? NSLocalizedString("topic.unfollow", comment: "")
                        : NSLocalizedString("topic.follow", comment: ""))
                }
                correctionsContext(for: topic)
            }
            .padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if store.isFollowing(topic.id) {
                    Button(role: .destructive) {
                        store.unfollow(topic.id)
                    } label: {
                        Label(NSLocalizedString("topic.unfollow", comment: ""), systemImage: "star.slash")
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

    @ViewBuilder
    private func correctionsContext(for topic: ParliamentaryTopic) -> some View {
        if topic.id == "justice",
           let snapshot = CorrectionsStatisticsDatabase.snapshot(),
           let latest = snapshot.latestAnnualStatistic {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Federal corrections", systemImage: "building.columns.fill")
                        .font(.caption.bold())
                    Spacer()
                    Text(CorrectionsStatisticsDatabase.fiscalYearLabel(snapshot.referenceFiscalYear))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    topicStat("Indigenous custody", percentLabel(latest.indigenousInCustodyPercent))
                    topicStat("Canada share", percentLabel(snapshot.indigenousPopulationShare.percentOfCanada))
                    topicStat("Recidivism", percentLabel(latest.recidivismRatePercent))
                }
                if let highlight = snapshot.ociHighlights.first {
                    Text(highlight.title)
                        .font(.caption2.weight(.semibold))
                }
                DataSourceBadge(source: .corrections())
                ForEach(CorrectionsStatisticsDatabase.sources(), id: \.url) { source in
                    Link(source.title, destination: source.url)
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func topicStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }
}
