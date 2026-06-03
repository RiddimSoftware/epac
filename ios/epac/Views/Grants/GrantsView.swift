import SwiftUI

private enum GrantsLayout {
    static let skeletonRows = 6
    static let retryDelaySeconds: Int64 = 2
    static let fetchLimit = 200
    static let rowSpacing = EpacSpacing.xs
    static let metadataSpacing: CGFloat = 6
    static let rowVerticalPadding = EpacSpacing.xs
    static let skeletonSpacing: CGFloat = 6
    static let skeletonCornerRadius: CGFloat = 3
    static let skeletonValueWidth: CGFloat = 100
    static let skeletonCompactHeight: CGFloat = 10
    static let skeletonTitleHeight: CGFloat = 14
    static let skeletonDetailWidth: CGFloat = 180
    static let skeletonVerticalPadding: CGFloat = 6
    static let filterChipSpacing: CGFloat = 8
    static let filterBarVerticalPadding: CGFloat = 8
    static let chipHorizontalPadding: CGFloat = 10
    static let chipVerticalPadding: CGFloat = 5
    static let citationBottomPadding: CGFloat = 8
    static let purposeLineLimit = 2
}

struct GrantsView: View {
    @State private var grants: [GrantContribution] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var isRetryDisabled = false
    @State private var selectedRecipientType: GrantContribution.RecipientTypeCategory?

    private var filtered: [GrantContribution] {
        var result = grants
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            result = result.filter {
                $0.recipientName.localizedCaseInsensitiveContains(q) ||
                $0.department.localizedCaseInsensitiveContains(q) ||
                $0.purpose.localizedCaseInsensitiveContains(q) ||
                $0.recipientLocation.localizedCaseInsensitiveContains(q)
            }
        }
        if let rt = selectedRecipientType {
            result = result.filter { $0.recipientTypeCategory == rt }
        }
        return result
    }

    var body: some View {
        Group {
            if isLoading && grants.isEmpty {
                List {
                    ForEach(0..<GrantsLayout.skeletonRows, id: \.self) { _ in
                        GrantRowSkeleton().shimmer(when: true)
                    }
                }
                .listStyle(.plain)
                .accessibilityLabel("Loading federal grants and contributions")
            } else if loadFailed && grants.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Grants",
                    message: "Federal grants data could not be loaded. Check your connection and try again.",
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), isEnabled: !isRetryDisabled, handler: {
                        isRetryDisabled = true
                        Task { try? await Task.sleep(for: .seconds(GrantsLayout.retryDelaySeconds)); isRetryDisabled = false }
                        Task { await load() }
                    })
                )
            } else if filtered.isEmpty && !grants.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Grants Found",
                    message: "No grants or contributions match your current filters.",
                    action: nil
                )
            } else {
                VStack(spacing: 0) {
                    typeFilterBar
                    List(filtered) { grant in
                        GrantRow(grant: grant)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
        }
        .navigationTitle("Grants & Contributions")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search recipient, department, or purpose"
        )
        .task { await load() }
        .safeAreaInset(edge: .bottom) {
            if !grants.isEmpty { citationFooter }
        }
    }

    // MARK: - Sub-views

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GrantsLayout.filterChipSpacing) {
                ForEach(GrantContribution.RecipientTypeCategory.allCases) { category in
                    FilterChip(
                        label: category.rawValue,
                        isSelected: selectedRecipientType == category
                    ) {
                        selectedRecipientType = selectedRecipientType == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, GrantsLayout.filterBarVerticalPadding)
        }
        .background(Color(.systemBackground))
    }

    private var citationFooter: some View {
        HStack {
            Link(destination: GrantContribution.datasetURL) {
                Text("Source: Treasury Board Secretariat Proactive Disclosure")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, GrantsLayout.citationBottomPadding)
        .background(Color(.systemBackground))
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            grants = try await GrantsService.fetchGrants(limit: GrantsLayout.fetchLimit)
        } catch {
            loadFailed = grants.isEmpty
        }
        isLoading = false
    }
}

// MARK: - GrantRow

struct GrantRow: View {
    let grant: GrantContribution

    var body: some View {
        VStack(alignment: .leading, spacing: GrantsLayout.rowSpacing) {
            HStack(spacing: GrantsLayout.metadataSpacing) {
                Text(grant.formattedAmount)
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if !grant.fiscalYear.isEmpty {
                    Text(grant.fiscalYear)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(grant.recipientName)
                .font(.subheadline)
                .lineLimit(1)
            Text(grant.department)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !grant.purpose.isEmpty {
                Text(grant.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(GrantsLayout.purposeLineLimit)
            }
            if !grant.recipientLocation.isEmpty {
                Label(grant.recipientLocation, systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, GrantsLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, GrantsLayout.chipHorizontalPadding)
                .padding(.vertical, GrantsLayout.chipVerticalPadding)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton

private struct GrantRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: GrantsLayout.skeletonSpacing) {
            RoundedRectangle(cornerRadius: GrantsLayout.skeletonCornerRadius)
                .frame(width: GrantsLayout.skeletonValueWidth, height: GrantsLayout.skeletonCompactHeight)
            RoundedRectangle(cornerRadius: GrantsLayout.skeletonCornerRadius)
                .frame(maxWidth: .infinity, minHeight: GrantsLayout.skeletonTitleHeight)
            RoundedRectangle(cornerRadius: GrantsLayout.skeletonCornerRadius)
                .frame(width: GrantsLayout.skeletonDetailWidth, height: GrantsLayout.skeletonCompactHeight)
        }
        .foregroundStyle(Color(.systemFill))
        .padding(.vertical, GrantsLayout.skeletonVerticalPadding)
    }
}
