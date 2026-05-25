//
//  HansardSearchView.swift
//  epac
//

import SwiftUI

private enum HansardSearchLayout {
    static let minimumQueryLength = 2
    static let rowSpacing: CGFloat = 4
    static let rowVerticalPadding = EpacSpacing.xxs
    static let partyBadgeHorizontalPadding: CGFloat = 6
    static let partyBadgeVerticalPadding: CGFloat = 2
    static let partyBadgeCornerRadius = EpacCornerRadius.xs
    static let partyBadgeFontSize: CGFloat = 10
    static let partyBadgeBackgroundOpacity = 0.15
    static let feedbackSpacing = EpacSpacing.s
    static let feedbackVerticalPadding = EpacSpacing.s
    static let emptyStateSpacing = EpacSpacing.s
    static let topicLineLimit = 2
    static let snippetLineLimit = 3
}

struct HansardSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let onResultTapped: (HansardSearchResult) -> Void

    @State private var viewModel = HansardSearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, HansardSearchLayout.feedbackVerticalPadding)
            }

            if let error = viewModel.error {
                errorBanner(error.localizedDescription)
            }

            content
        }
        .navigationTitle("Hansard Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search this session's Hansard"
        )
    }

    @ViewBuilder
    private var content: some View {
        let trimmedQuery = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if !viewModel.results.isEmpty {
            resultsList
        } else if viewModel.isLoading || viewModel.error != nil {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if trimmedQuery.count >= HansardSearchLayout.minimumQueryLength {
            noResultsView(for: trimmedQuery)
        } else {
            emptyPrompt
        }
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.results) { result in
                Button {
                    dismiss()
                    onResultTapped(result)
                } label: {
                    HansardSearchResultRow(result: result)
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard result.id == viewModel.results.last?.id,
                          viewModel.hasMore,
                          !viewModel.isLoading else { return }
                    Task { await viewModel.loadMore() }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyPrompt: some View {
        VStack(spacing: HansardSearchLayout.emptyStateSpacing) {
            Image(systemName: "text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Search debates by speaker, topic, or quote")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func noResultsView(for query: String) -> some View {
        ContentUnavailableView {
            Label("No Hansard matches", systemImage: "text.magnifyingglass")
        } description: {
            Text("No results in this session's Hansard for \"\(query)\".")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: HansardSearchLayout.feedbackSpacing) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

private struct HansardSearchResultRow: View {
    let result: HansardSearchResult

    private var party: Party {
        Party.partyWithAbbreviation(result.partyAbbreviation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HansardSearchLayout.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: HansardSearchLayout.feedbackSpacing) {
                if !result.speakerName.isEmpty {
                    Text(result.speakerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                if !result.partyAbbreviation.isEmpty {
                    partyBadge
                }
                Spacer()
            }

            Text(result.sittingDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(result.topic)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(HansardSearchLayout.topicLineLimit)

            if !result.snippet.isEmpty {
                Text(SnippetParser.parse(result.snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(HansardSearchLayout.snippetLineLimit)
            }
        }
        .padding(.vertical, HansardSearchLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Open debate")
    }

    private var partyBadge: some View {
        Text(result.partyAbbreviation)
            .font(.system(size: HansardSearchLayout.partyBadgeFontSize).weight(.semibold))
            .padding(.horizontal, HansardSearchLayout.partyBadgeHorizontalPadding)
            .padding(.vertical, HansardSearchLayout.partyBadgeVerticalPadding)
            .background(Color.party(party).opacity(HansardSearchLayout.partyBadgeBackgroundOpacity))
            .foregroundStyle(Color.party(party))
            .clipShape(RoundedRectangle(cornerRadius: HansardSearchLayout.partyBadgeCornerRadius))
    }

    private var accessibilityLabel: String {
        [
            result.speakerName,
            result.partyAbbreviation,
            result.sittingDate.formatted(date: .abbreviated, time: .omitted),
            result.topic
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}
