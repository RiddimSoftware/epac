import SwiftUI

struct GazetteDetailView: View {
    let entry: GazetteEntry

    private enum Layout {
        static let metadataSpacing: CGFloat = 6
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
                    HStack(spacing: Layout.metadataSpacing) {
                        Text(entry.part.localizedName)
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(entry.displayCategory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.title)
                        .font(.headline)
                    Text(entry.publicationDate, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, EpacSpacing.xs)
            }

            if !entry.summary.isEmpty {
                Section(NSLocalizedString("gazette.detail.summary", comment: "")) {
                    Text(entry.summary)
                        .font(.body)
                }
            }

            Section(NSLocalizedString("gazette.detail.source", comment: "")) {
                Link(destination: entry.url) {
                    Label {
                        Text(NSLocalizedString("gazette.detail.fullText", comment: ""))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "newspaper")
                    }
                }
                LabeledContent(
                    NSLocalizedString("gazette.detail.sourceLabel", comment: ""),
                    value: "\(NSLocalizedString("gazette.navTitle", comment: "")), \(entry.part.localizedName), \(entry.publicationDate.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("gazette.detail.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
