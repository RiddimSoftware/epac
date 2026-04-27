import SwiftUI

struct GazetteView: View {
    @State private var entries: [GazetteEntry] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var partFilter: GazettePart? = nil
    @State private var searchText = ""

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
                    ForEach(0..<6, id: \.self) { _ in
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
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), handler: { Task { await load() } })
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
        VStack(alignment: .leading, spacing: 4) {
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
                    .lineLimit(1)
                Spacer()
                Text(entry.publicationDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.title)
                .font(.subheadline)
                .lineLimit(2)
            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

private struct GazetteRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .frame(width: 80, height: 10)
            RoundedRectangle(cornerRadius: 3)
                .frame(maxWidth: .infinity, minHeight: 14)
            RoundedRectangle(cornerRadius: 3)
                .frame(width: 200, height: 10)
        }
        .foregroundStyle(Color(.systemFill))
        .padding(.vertical, 6)
    }
}
