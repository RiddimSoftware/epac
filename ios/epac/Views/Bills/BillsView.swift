//
//  BillsView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

struct BillsView: View {
    @State private var bills: [Bill] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var statusFilter: BillStatus? = nil
    @State private var typeFilter: BillTypeGroup? = nil

    private var filtered: [Bill] {
        bills.filter {
            (statusFilter == nil || $0.status == statusFilter) &&
            (typeFilter == nil || typeFilter!.matches($0))
        }
    }

    var body: some View {
        Group {
            if isLoading && bills.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(NSLocalizedString("bills.loading", comment: ""))
            } else if loadFailed && bills.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("bills.error.title", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(NSLocalizedString("bills.error.description", comment: ""))
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("bills.empty.title", comment: ""),
                    systemImage: "doc.text",
                    description: Text(NSLocalizedString("bills.empty.description", comment: ""))
                )
            } else {
                List(filtered) { bill in
                    NavigationLink(destination: BillDetailView(bill: bill)) {
                        BillRow(bill: bill)
                    }
                }
                .listStyle(.plain)
            }
        }
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
    }

    private var filterIsActive: Bool { statusFilter != nil || typeFilter != nil }

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
                .lineLimit(2)
            if !bill.sponsorName.isEmpty {
                Text(bill.sponsorName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !bill.currentStage.isEmpty {
                Text(bill.currentStage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
    }
}
