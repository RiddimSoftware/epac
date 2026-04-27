//
//  BillsView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI
import ActivityView

struct BillsView: View {
    @State private var bills: [Bill] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var statusFilter: BillStatus? = BillsView.loadStatusFilter()
    @State private var typeFilter: BillTypeGroup? = nil
    @State private var billStore = BillFollowStore.shared
    @State private var searchText = ""
    @State private var shareItems: ActivityItem?
    @Environment(NavigationRouter.self) private var router

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
                    ForEach(0..<5, id: \.self) { _ in
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
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), handler: { Task { await load() } })
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
                    NavigationLink(destination: BillDetailView(bill: bill)) {
                        BillRow(bill: bill)
                    }
                    .contextMenu {
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
            UserDefaults.standard.set(Date(), forKey: "epac.sync.bills")
            // Detect stage changes for followed bills and schedule notifications
            let store = BillFollowStore.shared
            let changes = store.detectChanges(in: bills)
            for change in changes {
                BillNotificationScheduler.schedule(change)
            }
            await TopicNotificationScheduler.checkAndNotify(bills: bills)
        } catch {
            loadFailed = true
        }
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

// MARK: - Bill Row

struct BillRow: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(bill.number)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.bold)
                BillStatusBadge(status: bill.status)
                Spacer()
                if !bill.billType.shortName.isEmpty {
                    Text(bill.billType.shortName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(bill.title)
                .font(.subheadline)
                .lineLimit(3)
            if !bill.sponsorName.isEmpty {
                Text(bill.sponsorName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !bill.currentStage.isEmpty {
                Text(bill.currentStage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(billAccessibilityLabel)
    }

    private var billAccessibilityLabel: String {
        var parts = [bill.number, bill.status.displayName]
        if !bill.title.isEmpty { parts.append(bill.title) }
        if !bill.sponsorName.isEmpty { parts.append(bill.sponsorName) }
        if !bill.currentStage.isEmpty && bill.currentStage != bill.status.displayName {
            parts.append(bill.currentStage)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Status Badge

struct BillStatusBadge: View {
    let status: BillStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color)
            .clipShape(Capsule())
            // BillRow composes the full label; badge is redundant for VoiceOver
            .accessibilityHidden(true)
    }
}
