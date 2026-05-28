//
//  BillsView.swift
//  epac
//
//  Created on 2026-04-27.
//

import ActivityView
import SwiftUI

private enum BillsLayout {
    static let listColumnMinWidth: CGFloat = 320
    static let listColumnIdealWidth: CGFloat = 360
    static let listColumnMaxWidth: CGFloat = 420
    static let selectedRowOpacity = 0.14
    static let skeletonRows = 5
    static let retryDelaySeconds: Int64 = 2
    static let rowSpacing = EpacSpacing.xs
    static let badgeRowSpacing: CGFloat = 6
    static let rowVerticalPadding = EpacSpacing.xs
    static let newIndicatorFontSize: CGFloat = 6
    static let statusBadgeHorizontalPadding: CGFloat = 6
    static let statusBadgeVerticalPadding = EpacSpacing.xxs
}

struct BillsTabRoot: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selectedBill: Bill?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        if horizontalSizeClass == .compact {
            BillsView()
        } else {
            regularBillsSplitView
        }
    }

    private var regularBillsSplitView: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            BillsView(selection: $selectedBill)
                .navigationSplitViewColumnWidth(
                    min: BillsLayout.listColumnMinWidth,
                    ideal: BillsLayout.listColumnIdealWidth,
                    max: BillsLayout.listColumnMaxWidth
                )
        } detail: {
            NavigationStack {
                if let selectedBill {
                    BillDetailView(bill: selectedBill)
                        .id(BillsSelection.identity(for: selectedBill))
                } else {
                    Text(NSLocalizedString("bills.detail.placeholder", comment: ""))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("bills-detail-placeholder")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct BillsView: View {
    @State private var bills: [Bill] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var statusFilter: BillStatus? = BillsView.loadStatusFilter()
    @State private var typeFilter: BillTypeGroup?
    @State private var billStore = BillFollowStore.shared
    @State private var searchText = ""
    @State private var shareItems: ActivityItem?
    @State private var newSince: Date? = UserDefaults.standard.object(forKey: "epac.bills.newSince") as? Date
    @State private var isRetryDisabled = false
    @Environment(NavigationRouter.self) private var router
    private let selection: Binding<Bill?>?

    init(selection: Binding<Bill?>? = nil) {
        self.selection = selection
    }

    private var filtered: [Bill] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return bills.filter {
            (statusFilter == nil || $0.status == statusFilter) &&
            (typeFilter == nil || typeFilter!.matches($0)) &&
            (q.isEmpty || $0.number.localizedCaseInsensitiveContains(q) || $0.title.localizedCaseInsensitiveContains(q))
        }
    }

    var body: some View {
        Group {
            if isLoading && bills.isEmpty {
                List {
                    ForEach(0..<BillsLayout.skeletonRows, id: \.self) { _ in
                        BillRowSkeleton()
                            .shimmer(when: true)
                    }
                }
                .listStyle(.plain)
                .accessibilityLabel(NSLocalizedString("bills.loading", comment: ""))
            } else if loadFailed && bills.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: NSLocalizedString("bills.error.title", comment: ""),
                    message: NSLocalizedString("bills.error.description", comment: ""),
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), isEnabled: !isRetryDisabled, handler: {
                        isRetryDisabled = true
                        Task { try? await Task.sleep(for: .seconds(BillsLayout.retryDelaySeconds)); isRetryDisabled = false }
                        Task { await load() }
                    })
                )
            } else if filtered.isEmpty && filterIsActive {
                EmptyStateView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: NSLocalizedString("bills.noMatch.title", comment: ""),
                    message: NSLocalizedString("bills.noMatch.description", comment: ""),
                    action: EmptyStateAction(label: NSLocalizedString("bills.filter.all", comment: ""), handler: {
                        statusFilter = nil; typeFilter = nil
                    })
                )
            } else if filtered.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: NSLocalizedString("bills.empty.title", comment: ""),
                    message: NSLocalizedString("bills.empty.description", comment: ""),
                    action: nil
                )
            } else {
                List(filtered) { bill in
                    billRow(for: bill)
                }
                .listStyle(.plain)
                .refreshable {
                    bills = []
                    await load()
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: NSLocalizedString("bills.search.prompt", comment: ""))
        .navigationTitle(NSLocalizedString("bills.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section(NSLocalizedString("bills.filter.status", comment: "")) {
                        filterButton(label: NSLocalizedString("bills.filter.all", comment: ""),
                                     isActive: statusFilter == nil) { statusFilter = nil }
                        filterButton(label: BillStatus.inProgress.displayName,
                                     isActive: statusFilter == .inProgress) { statusFilter = .inProgress }
                        filterButton(label: BillStatus.royalAssent.displayName,
                                     isActive: statusFilter == .royalAssent) { statusFilter = .royalAssent }
                        filterButton(label: BillStatus.defeated.displayName,
                                     isActive: statusFilter == .defeated) { statusFilter = .defeated }
                    }
                    Section(NSLocalizedString("bills.filter.type", comment: "")) {
                        filterButton(label: NSLocalizedString("bills.filter.all", comment: ""),
                                     isActive: typeFilter == nil) { typeFilter = nil }
                        filterButton(label: NSLocalizedString("bill.type.short.gov", comment: ""),
                                     isActive: typeFilter == .government) { typeFilter = .government }
                        filterButton(label: NSLocalizedString("bill.type.short.pmb", comment: ""),
                                     isActive: typeFilter == .privateMember) { typeFilter = .privateMember }
                        filterButton(label: NSLocalizedString("bill.type.short.senate", comment: ""),
                                     isActive: typeFilter == .senate) { typeFilter = .senate }
                    }
                } label: {
                    Label(NSLocalizedString("bills.filter", comment: ""),
                          systemImage: filterIsActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(NSLocalizedString("bills.filter", comment: ""))
            }
        }
        .task { await load() }
        .onChange(of: statusFilter) { saveStatusFilter() }
        .activitySheet($shareItems)
    }

    private var filterIsActive: Bool { statusFilter != nil || typeFilter != nil }

    @ViewBuilder
    private func billRow(for bill: Bill) -> some View {
        if let selection {
            Button {
                BillsSelection.select(bill, selection: selection)
            } label: {
                BillRow(bill: bill, newSince: newSince)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .listRowBackground(
                BillsSelection.isSelected(bill, selectedBill: selection.wrappedValue)
                    ? Color.accentColor.opacity(BillsLayout.selectedRowOpacity)
                    : Color.clear
            )
            .accessibilityAddTraits(
                BillsSelection.isSelected(bill, selectedBill: selection.wrappedValue)
                    ? [.isSelected]
                    : []
            )
            .contextMenu {
                billContextMenuItems(for: bill)
            }
        } else {
            NavigationLink(destination: BillDetailView(bill: bill)) {
                BillRow(bill: bill, newSince: newSince)
            }
            .contextMenu {
                billContextMenuItems(for: bill)
            }
        }
    }

    @ViewBuilder
    private func billContextMenuItems(for bill: Bill) -> some View {
        Button {
            billStore.toggle(bill)
        } label: {
            Label(
                billStore.isFollowing(bill.number)
                    ? NSLocalizedString("bill.unfollow", comment: "")
                    : NSLocalizedString("bill.follow", comment: ""),
                systemImage: billStore.isFollowing(bill.number) ? "doc.badge.clock.fill" : "doc.badge.clock"
            )
        }
        Button {
            shareItems = BillSharer.activityItem(for: bill)
        } label: {
            Label(NSLocalizedString("bill.share", comment: ""), systemImage: "square.and.arrow.up")
        }
        Button {
            router.pendingSearchQuery = bill.number
            router.selectedTab = .search
        } label: {
            Label(NSLocalizedString("bill.contextMenu.seeVotes", comment: ""), systemImage: "checkmark.ballot")
        }
    }

    // MARK: - Filter persistence

    private static let statusFilterKey = "bills.filter.status.persisted"

    private static func loadStatusFilter() -> BillStatus? {
        guard let raw = UserDefaults.standard.string(forKey: statusFilterKey) else { return nil }
        return BillStatus(rawValue: raw)
    }

    private func saveStatusFilter() {
        if let status = statusFilter {
            UserDefaults.standard.set(status.rawValue, forKey: Self.statusFilterKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.statusFilterKey)
        }
    }

    @ViewBuilder
    private func filterButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(label, systemImage: isActive ? "checkmark.circle.fill" : "circle")
        }
    }

    // MARK: - Data

    private func load() async {
        guard bills.isEmpty else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            bills = try await BillsService.fetchBills()
            refreshSelectedBill(from: bills)
            UserDefaults.standard.set(Date(), forKey: "epac.sync.bills")
            // Track the newest introduction date so the next session knows what's "new".
            if let maxDate = bills.compactMap(\.introducedDate).max() {
                let current = UserDefaults.standard.object(forKey: "epac.bills.latestSeen") as? Date
                if current.map({ maxDate > $0 }) ?? true {
                    UserDefaults.standard.set(maxDate, forKey: "epac.bills.latestSeen")
                }
            }
            BillFollowStore.shared.updateStoredState(in: bills)
        } catch {
            loadFailed = true
        }
    }

    private func refreshSelectedBill(from loadedBills: [Bill]) {
        guard let selection,
              let selectedBill = selection.wrappedValue,
              let refreshedBill = BillsSelection.matching(selectedBill, in: loadedBills) else {
            return
        }

        selection.wrappedValue = refreshedBill
    }
}

// MARK: - Filter group (collapses senate bill variants)

enum BillTypeGroup: Equatable {
    case government
    case privateMember
    case senate

    func matches(_ bill: Bill) -> Bool {
        switch self {
        case .government:    return bill.billType == .houseGovernment
        case .privateMember: return bill.billType == .privateMember
        case .senate:        return bill.billType == .senateGovernment
                                 || bill.billType == .senatePublic
                                 || bill.billType == .senatePrivate
        }
    }
}

enum BillsSelection {
    static func select(_ bill: Bill, selection: Binding<Bill?>) {
        selection.wrappedValue = bill
    }

    static func isSelected(_ bill: Bill, selectedBill: Bill?) -> Bool {
        guard let selectedBill else { return false }
        return identity(for: bill) == identity(for: selectedBill)
    }

    static func matching(_ selectedBill: Bill, in bills: [Bill]) -> Bill? {
        bills.first { identity(for: $0) == identity(for: selectedBill) }
    }

    static func identity(for bill: Bill) -> String {
        "\(bill.parliament)-\(bill.session)-\(bill.number.lowercased())"
    }
}

// MARK: - Bill Row

struct BillRow: View {
    let bill: Bill
    var newSince: Date?

    private var isNew: Bool {
        guard let newSince, let introduced = bill.introducedDate else { return false }
        return introduced > newSince
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BillsLayout.rowSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BillsLayout.badgeRowSpacing) {
                    billNumberLabel
                    BillStatusBadge(status: bill.status)
                    Spacer()
                    billTypeLabel
                }
                VStack(alignment: .leading, spacing: BillsLayout.rowSpacing) {
                    HStack(spacing: BillsLayout.badgeRowSpacing) {
                        billNumberLabel
                        BillStatusBadge(status: bill.status)
                    }
                    billTypeLabel
                }
            }
            Text(bill.title)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !bill.sponsorName.isEmpty {
                Text(bill.sponsorName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !bill.currentStage.isEmpty {
                Text(bill.currentStage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, BillsLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(billAccessibilityLabel)
    }

    private var billAccessibilityLabel: String {
        var parts: [String] = []
        if isNew { parts.append(NSLocalizedString("bill.new.accessibility", comment: "")) }
        parts += [bill.number, bill.status.displayName]
        if !bill.title.isEmpty { parts.append(bill.title) }
        if !bill.sponsorName.isEmpty { parts.append(bill.sponsorName) }
        if !bill.currentStage.isEmpty && bill.currentStage != bill.status.displayName {
            parts.append(bill.currentStage)
        }
        return parts.joined(separator: ", ")
    }

    private var billNumberLabel: some View {
        HStack(spacing: BillsLayout.rowSpacing) {
            Text(bill.number)
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
            if isNew {
                Image(systemName: "circle.fill")
                    .font(.system(size: BillsLayout.newIndicatorFontSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var billTypeLabel: some View {
        if !bill.billType.shortName.isEmpty {
            Text(bill.billType.shortName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Status Badge

struct BillStatusBadge: View {
    let status: BillStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, BillsLayout.statusBadgeHorizontalPadding)
            .padding(.vertical, BillsLayout.statusBadgeVerticalPadding)
            .background(status.color)
            .clipShape(Capsule())
            // BillRow composes the full label; badge is redundant for VoiceOver
            .accessibilityHidden(true)
    }
}
