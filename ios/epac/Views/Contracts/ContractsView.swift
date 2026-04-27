import SwiftUI

struct ContractsView: View {
    @State private var contracts: [GovernmentContract] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var searchText = ""

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
                    ForEach(0..<6, id: \.self) { _ in
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
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), handler: { Task { await load() } })
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
            contracts = try await ContractsService.fetchTopContracts(limit: 100)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
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
                .lineLimit(1)
            Text(contract.department)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !contract.purpose.isEmpty {
                Text(contract.purpose)
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

private struct FederalContractRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3).frame(width: 100, height: 10)
            RoundedRectangle(cornerRadius: 3).frame(maxWidth: .infinity, minHeight: 14)
            RoundedRectangle(cornerRadius: 3).frame(width: 180, height: 10)
        }
        .foregroundStyle(Color(.systemFill))
        .padding(.vertical, 6)
    }
}
