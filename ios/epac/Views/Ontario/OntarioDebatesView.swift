//
//  OntarioDebatesView.swift
//  epac
//
//  Shows recent Queen's Park (Ontario Legislative Assembly) debate transcripts
//  as a list of links to ola.org. Data is fetched on appear with no caching
//  (debate list is small; MPP data is cached separately).
//

import SwiftUI

private enum Layout {
    static let rowTextSpacing: CGFloat = 3
}

struct OntarioDebatesView: View {
    @State private var debates: [OntarioDebateDay] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && debates.isEmpty {
                ProgressView()
            } else if debates.isEmpty && !isLoading {
                ContentUnavailableView(
                    NSLocalizedString("ontario.debates.empty.title", comment: ""),
                    systemImage: "building.columns",
                    description: Text(NSLocalizedString("ontario.debates.empty.description", comment: ""))
                )
            } else {
                List(debates) { day in
                    Link(destination: day.publicationURL) {
                        HStack {
                            VStack(alignment: .leading, spacing: Layout.rowTextSpacing) {
                                Text(NSLocalizedString("ontario.debates.title", comment: ""))
                                    .font(.subheadline.weight(.semibold))
                                if let date = day.date {
                                    Text(date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(
                        day.date.map { date in
                            "\(NSLocalizedString("ontario.debates.title", comment: "")), \(date.formatted(date: .long, time: .omitted))"
                        } ?? NSLocalizedString("ontario.debates.title", comment: "")
                    )
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("ontario.debates.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        debates = await OntarioLegislatureService.fetchRecentDebates()
    }
}
