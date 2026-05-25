import SwiftUI

private enum ContractsLayout {
    static let skeletonRows = 6
    static let retryDelaySeconds: Int64 = 2
    static let fetchLimit = 100
    static let rowSpacing = EpacSpacing.xs
    static let metadataSpacing: CGFloat = 6
    static let singleLineLimit = 1
    static let summaryLineLimit = 2
    static let rowVerticalPadding = EpacSpacing.xs
    static let skeletonSpacing: CGFloat = 6
    static let skeletonCornerRadius: CGFloat = 3
    static let skeletonValueWidth: CGFloat = 100
    static let skeletonCompactHeight: CGFloat = 10
    static let skeletonTitleHeight: CGFloat = 14
    static let skeletonDetailWidth: CGFloat = 180
    static let skeletonVerticalPadding: CGFloat = 6
}

struct ContractsView: View {
    @State private var contracts: [GovernmentContract] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var isRetryDisabled = false

    private var filtered: [GovernmentContract] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return contracts }
        return contracts.filter {
            $0.vendor.localizedCaseInsensitiveContains(q) ||
            $0.department.localizedCaseInsensitiveContains(q) ||
            $0.purpose.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Group {
            if isLoading && contracts.isEmpty {
                List {
                    ForEach(0..<ContractsLayout.skeletonRows, id: \.self) { _ in
                        FederalContractRowSkeleton().shimmer(when: true)
                    }
                }
                .listStyle(.plain)
                .accessibilityLabel(NSLocalizedString("contracts.loading", comment: ""))
            } else if loadFailed && contracts.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: NSLocalizedString("contracts.error.title", comment: ""),
                    message: NSLocalizedString("contracts.error.description", comment: ""),
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), isEnabled: !isRetryDisabled, handler: {
                        isRetryDisabled = true
                        Task { try? await Task.sleep(for: .seconds(ContractsLayout.retryDelaySeconds)); isRetryDisabled = false }
                        Task { await load() }
                    })
                )
            } else if filtered.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: NSLocalizedString("contracts.empty.title", comment: ""),
                    message: NSLocalizedString("contracts.empty.description", comment: ""),
                    action: nil
                )
            } else {
                List(filtered) { contract in
                    NavigationLink(destination: FederalContractDetailView(contract: contract)) {
                        FederalContractRow(contract: contract)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle(NSLocalizedString("contracts.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: NSLocalizedString("contracts.search.prompt", comment: "")
        )
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            contracts = try await ContractsService.fetchTopContracts(limit: ContractsLayout.fetchLimit)
        } catch {
            loadFailed = contracts.isEmpty
        }
        isLoading = false
    }
}

// MARK: - Row

private struct FederalContractRow: View {
    let contract: GovernmentContract

    var body: some View {
        VStack(alignment: .leading, spacing: ContractsLayout.rowSpacing) {
            HStack(spacing: ContractsLayout.metadataSpacing) {
                if contract.isHighValue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(contract.formattedValue)
                    .font(.caption.bold())
                    .foregroundStyle(contract.isHighValue ? Color.orange : Color.accentColor)
                Spacer()
                Text(contract.contractDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(contract.vendor)
                .font(.subheadline)
                .lineLimit(ContractsLayout.singleLineLimit)
            Text(contract.department)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(ContractsLayout.singleLineLimit)
            if !contract.purpose.isEmpty {
                Text(contract.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(ContractsLayout.summaryLineLimit)
            }
        }
        .padding(.vertical, ContractsLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

private struct FederalContractRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ContractsLayout.skeletonSpacing) {
            RoundedRectangle(cornerRadius: ContractsLayout.skeletonCornerRadius)
                .frame(width: ContractsLayout.skeletonValueWidth, height: ContractsLayout.skeletonCompactHeight)
            RoundedRectangle(cornerRadius: ContractsLayout.skeletonCornerRadius)
                .frame(maxWidth: .infinity, minHeight: ContractsLayout.skeletonTitleHeight)
            RoundedRectangle(cornerRadius: ContractsLayout.skeletonCornerRadius)
                .frame(width: ContractsLayout.skeletonDetailWidth, height: ContractsLayout.skeletonCompactHeight)
        }
        .foregroundStyle(Color(.systemFill))
        .padding(.vertical, ContractsLayout.skeletonVerticalPadding)
    }
}
