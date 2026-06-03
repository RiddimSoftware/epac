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
    static let filterSheetDetent: PresentationDetent = .medium
}

struct ContractsView: View {
    let initialDepartmentFilter: String

    @State private var contracts: [GovernmentContract] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var isRetryDisabled = false
    @State private var showFilters = false

    // Filter state
    @State private var filterDepartment: String
    @State private var filterMinAmount: String = ""
    @State private var filterMaxAmount: String = ""
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var filterContractType: String = ""

    private var hasActiveFilters: Bool {
        !filterDepartment.isEmpty ||
        !filterMinAmount.isEmpty ||
        !filterMaxAmount.isEmpty ||
        filterStartDate != nil ||
        filterEndDate != nil ||
        !filterContractType.isEmpty
    }

    init(initialDepartmentFilter: String = "") {
        self.initialDepartmentFilter = initialDepartmentFilter
        self._filterDepartment = State(initialValue: initialDepartmentFilter)
    }

    private var filtered: [GovernmentContract] {
        var result = contracts

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            result = result.filter {
                $0.vendor.localizedCaseInsensitiveContains(q) ||
                $0.department.localizedCaseInsensitiveContains(q) ||
                $0.purpose.localizedCaseInsensitiveContains(q)
            }
        }

        let dept = filterDepartment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dept.isEmpty {
            result = result.filter { $0.department.localizedCaseInsensitiveContains(dept) }
        }

        if let min = Double(filterMinAmount) {
            result = result.filter { $0.value >= min }
        }
        if let max = Double(filterMaxAmount) {
            result = result.filter { $0.value <= max }
        }

        if let start = filterStartDate {
            result = result.filter { $0.contractDate >= start }
        }
        if let end = filterEndDate {
            result = result.filter { $0.contractDate <= end }
        }

        let ctype = filterContractType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctype.isEmpty {
            result = result.filter { $0.contractType.localizedCaseInsensitiveContains(ctype) }
        }

        return result
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Label(NSLocalizedString("contracts.filter.button", comment: ""), systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(NSLocalizedString("contracts.filter.button", comment: ""))
                .accessibilityHint(hasActiveFilters ? NSLocalizedString("contracts.filter.active", comment: "") : "")
            }
        }
        .sheet(isPresented: $showFilters) {
            ContractFiltersView(
                department: $filterDepartment,
                minAmount: $filterMinAmount,
                maxAmount: $filterMaxAmount,
                startDate: $filterStartDate,
                endDate: $filterEndDate,
                contractType: $filterContractType
            )
        }
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

// MARK: - Filter sheet

private struct ContractFiltersView: View {
    @Binding var department: String
    @Binding var minAmount: String
    @Binding var maxAmount: String
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Binding var contractType: String

    @Environment(\.dismiss) private var dismiss
    @State private var useStartDate = false
    @State private var useEndDate = false
    @State private var localStart = Date()
    @State private var localEnd = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("contracts.filter.department", comment: "")) {
                    TextField(NSLocalizedString("contracts.filter.department.placeholder", comment: ""), text: $department)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section(NSLocalizedString("contracts.filter.contractType", comment: "")) {
                    TextField(NSLocalizedString("contracts.filter.contractType.placeholder", comment: ""), text: $contractType)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section(NSLocalizedString("contracts.filter.amount", comment: "")) {
                    LabeledContent(NSLocalizedString("contracts.filter.minAmount", comment: "")) {
                        TextField("0", text: $minAmount)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    LabeledContent(NSLocalizedString("contracts.filter.maxAmount", comment: "")) {
                        TextField(NSLocalizedString("contracts.filter.noLimit", comment: ""), text: $maxAmount)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                Section(NSLocalizedString("contracts.filter.dateRange", comment: "")) {
                    Toggle(NSLocalizedString("contracts.filter.fromDate", comment: ""), isOn: $useStartDate)
                    if useStartDate {
                        DatePicker("", selection: $localStart, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .onChange(of: localStart) { _, v in startDate = v }
                    }
                    Toggle(NSLocalizedString("contracts.filter.toDate", comment: ""), isOn: $useEndDate)
                    if useEndDate {
                        DatePicker("", selection: $localEnd, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .onChange(of: localEnd) { _, v in endDate = v }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        department = ""
                        minAmount = ""
                        maxAmount = ""
                        contractType = ""
                        startDate = nil
                        endDate = nil
                        useStartDate = false
                        useEndDate = false
                    } label: {
                        Text(NSLocalizedString("contracts.filter.clearAll", comment: ""))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("contracts.filter.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("dataSource.done", comment: "")) {
                        if useStartDate { startDate = localStart }
                        if useEndDate { endDate = localEnd }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let s = startDate { useStartDate = true; localStart = s }
                if let e = endDate { useEndDate = true; localEnd = e }
            }
        }
        .presentationDetents([ContractsLayout.filterSheetDetent, .large])
    }
}

// MARK: - Row

struct FederalContractRow: View {
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
