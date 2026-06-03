//
//  TopicsView.swift
//  epac
//

import Observation
import SwiftUI

private enum TopicsLayout {
    static let minimumSearchLength = 2
    static let rowSpacing = EpacSpacing.s
    static let rowVerticalPadding = EpacSpacing.xxs
    static let keywordPreviewLimit = 3
    static let contextSpacing: CGFloat = 6
    static let statRowSpacing: CGFloat = 12
    static let contextHorizontalPadding: CGFloat = 10
    static let contextVerticalPadding = EpacSpacing.s
    static let contextCornerRadius = EpacCornerRadius.s
    static let statSpacing = EpacSpacing.xxs
}

struct TopicsView: View {
    @State private var viewModel: TopicsViewModel

    init(
        topicPreferenceStore: any TopicPreferenceStore = TopicFollowStoreAdapter(),
        initialSearchText: String = ""
    ) {
        _viewModel = State(
            initialValue: TopicsViewModel(
                preferences: topicPreferenceStore,
                initialSearchText: initialSearchText
            )
        )
    }

    var body: some View {
        List(viewModel.filteredTopics) { topic in
            VStack(alignment: .leading, spacing: TopicsLayout.rowSpacing) {
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
                        viewModel.toggle(topic)
                    } label: {
                        Image(systemName: viewModel.isFollowing(topic) ? "star.fill" : "star")
                            .foregroundStyle(viewModel.isFollowing(topic) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isFollowing(topic)
                        ? NSLocalizedString("topic.unfollow", comment: "")
                        : NSLocalizedString("topic.follow", comment: ""))
                }
                correctionsContext(for: topic)
            }
            .padding(.vertical, TopicsLayout.rowVerticalPadding)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if viewModel.isFollowing(topic) {
                    Button(role: .destructive) {
                        viewModel.unfollow(topic)
                    } label: {
                        Label(NSLocalizedString("topic.unfollow", comment: ""), systemImage: "star.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $viewModel.searchText,
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
            Text(topic.keywords.prefix(TopicsLayout.keywordPreviewLimit).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func correctionsContext(for topic: ParliamentaryTopic) -> some View {
        if topic.id == "justice",
           let snapshot = CorrectionsStatisticsDatabase.snapshot(),
           let latest = snapshot.latestAnnualStatistic {
            VStack(alignment: .leading, spacing: TopicsLayout.contextSpacing) {
                HStack {
                    Label("Federal corrections", systemImage: "building.columns.fill")
                        .font(.caption.bold())
                    Spacer()
                    Text(CorrectionsStatisticsDatabase.fiscalYearLabel(snapshot.referenceFiscalYear))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: TopicsLayout.statRowSpacing) {
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
            .padding(.horizontal, TopicsLayout.contextHorizontalPadding)
            .padding(.vertical, TopicsLayout.contextVerticalPadding)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: TopicsLayout.contextCornerRadius))
        }
    }

    private func topicStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: TopicsLayout.statSpacing) {
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

@MainActor
@Observable
final class TopicsViewModel {
    var searchText = ""
    private let preferences: any TopicPreferenceStore
    private var followedIDs: Set<String>

    init(
        preferences: any TopicPreferenceStore = TopicFollowStoreAdapter(),
        initialSearchText: String = ""
    ) {
        self.preferences = preferences
        self.followedIDs = preferences.followedTopicIDs()
        self.searchText = initialSearchText
    }

    var filteredTopics: [ParliamentaryTopic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= TopicsLayout.minimumSearchLength else { return ParliamentaryTopic.all }
        return ParliamentaryTopic.all.filter {
            $0.localizedName.localizedCaseInsensitiveContains(query) ||
                $0.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func isFollowing(_ topic: ParliamentaryTopic) -> Bool {
        followedIDs.contains(topic.id)
    }

    func toggle(_ topic: ParliamentaryTopic) {
        preferences.toggle(topic.id)
        refreshFollowedIDs()
    }

    func unfollow(_ topic: ParliamentaryTopic) {
        preferences.unfollow(topic.id)
        refreshFollowedIDs()
    }

    private func refreshFollowedIDs() {
        followedIDs = preferences.followedTopicIDs()
    }
}
