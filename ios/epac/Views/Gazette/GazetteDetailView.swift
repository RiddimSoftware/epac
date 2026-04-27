import SwiftUI

struct GazetteDetailView: View {
    let entry: GazetteEntry

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
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
                .padding(.vertical, 4)
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
                    value: "Canada Gazette, \(entry.part.localizedName), \(entry.publicationDate.formatted(date: .abbreviated, time: .omitted))"
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
