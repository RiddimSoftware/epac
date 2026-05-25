import SwiftUI

private enum GazetteLayout {
    static let skeletonRows = 6
    static let retryDelaySeconds: Int64 = 2
    static let rowSpacing = EpacSpacing.xs
    static let metadataSpacing: CGFloat = 6
    static let titleLineLimit = 2
    static let rowVerticalPadding = EpacSpacing.xs
    static let skeletonSpacing: CGFloat = 6
    static let skeletonCornerRadius: CGFloat = 3
    static let skeletonMetadataWidth: CGFloat = 80
    static let skeletonCompactHeight: CGFloat = 10
    static let skeletonTitleHeight: CGFloat = 14
    static let skeletonDetailWidth: CGFloat = 200
    static let skeletonVerticalPadding: CGFloat = 6
}

struct GazetteView: View {
    @State private var entries: [GazetteEntry] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var partFilter: GazettePart?
    @State private var searchText = ""
    @State private var isRetryDisabled = false

    private var filtered: [GazetteEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter {
            (partFilter == nil || $0.part == partFilter) &&
            (q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) ||
             $0.category.localizedCaseInsensitiveContains(q) ||
             $0.summary.localizedCaseInsensitiveContains(q))
        }
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                List {
                    ForEach(0..<GazetteLayout.skeletonRows, id: \.self) { _ in
                        GazetteRowSkeleton()
                            .shimmer(when: true)
                    }
                }
                .listStyle(.plain)
                .accessibilityLabel(NSLocalizedString("gazette.loading", comment: ""))
            } else if loadFailed && entries.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: NSLocalizedString("gazette.error.title", comment: ""),
                    message: NSLocalizedString("gazette.error.description", comment: ""),
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), isEnabled: !isRetryDisabled, handler: {
                        isRetryDisabled = true
                        Task { try? await Task.sleep(for: .seconds(GazetteLayout.retryDelaySeconds)); isRetryDisabled = false }
                        Task { await load() }
                    })
                )
            } else if filtered.isEmpty {
                EmptyStateView(
                    icon: "newspaper",
                    title: NSLocalizedString("gazette.empty.title", comment: ""),
                    message: NSLocalizedString("gazette.empty.description", comment: ""),
                    action: partFilter != nil
                        ? EmptyStateAction(label: NSLocalizedString("gazette.filter.all", comment: ""), handler: { partFilter = nil })
                        : nil
                )
            } else {
                List(filtered) { entry in
                    NavigationLink(destination: GazetteDetailView(entry: entry)) {
                        GazetteRow(entry: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("gazette.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: NSLocalizedString("gazette.search.prompt", comment: "")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        partFilter = nil
                    } label: {
                        Label(NSLocalizedString("gazette.filter.all", comment: ""),
                              systemImage: partFilter == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(GazettePart.allCases) { part in
                        Button {
                            partFilter = partFilter == part ? nil : part
                        } label: {
                            Label(part.localizedName,
                                  systemImage: partFilter == part ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle\(partFilter != nil ? ".fill" : "")")
                        .accessibilityLabel(NSLocalizedString("gazette.filter.label", comment: ""))
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            entries = try await GazetteService.fetchAll()
        } catch {
            loadFailed = entries.isEmpty
        }
        isLoading = false
    }
}

// MARK: - Row

private struct GazetteRow: View {
    let entry: GazetteEntry

    var body: some View {
        VStack(alignment: .leading, spacing: GazetteLayout.rowSpacing) {
            HStack(spacing: GazetteLayout.metadataSpacing) {
                Text(entry.part.localizedName)
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(entry.displayCategory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(entry.publicationDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.title)
                .font(.subheadline)
                .lineLimit(GazetteLayout.titleLineLimit)
            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(GazetteLayout.titleLineLimit)
            }
        }
        .padding(.vertical, GazetteLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

private struct GazetteRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: GazetteLayout.skeletonSpacing) {
            RoundedRectangle(cornerRadius: GazetteLayout.skeletonCornerRadius)
                .frame(width: GazetteLayout.skeletonMetadataWidth, height: GazetteLayout.skeletonCompactHeight)
            RoundedRectangle(cornerRadius: GazetteLayout.skeletonCornerRadius)
                .frame(maxWidth: .infinity, minHeight: GazetteLayout.skeletonTitleHeight)
            RoundedRectangle(cornerRadius: GazetteLayout.skeletonCornerRadius)
                .frame(width: GazetteLayout.skeletonDetailWidth, height: GazetteLayout.skeletonCompactHeight)
        }
        .foregroundStyle(Color(.systemFill))
        .padding(.vertical, GazetteLayout.skeletonVerticalPadding)
    }
}
