//
//  ExpenditureDetailView.swift
//  epac
//
//  Created by Sunny on 2026-01-29.
//

import ActivityView
import SwiftData
import SwiftUI

private enum ExpenditureDetailLayout {
    static let loadingCornerRadius: CGFloat = 10
    static let expandedRotationDegrees: Double = 90
    static let headerVerticalPadding: CGFloat = 12
    static let rowTextSpacing = EpacSpacing.xxs
    static let rowDetailSpacing = EpacSpacing.xs
    static let rowVerticalPadding = EpacSpacing.xs
}

struct ExpenditureDetailView: View {
    let expenditure: SummaryExpenditure
    @EnvironmentObject var fetch: Fetch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel = ExpenditureDetailViewModel()
    @State private var item: ActivityItem?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section(header: SectionHeader(
                    title: "Travel",
                    total: expenditure.travel,
                    isCollapsed: viewModel.travelCollapsed,
                    shareAction: {
                        let sorted = expenditure.travelClaims.sorted { $0.total > $1.total }
                        item = viewModel.shareSection(expenditure: expenditure, category: "Travel", total: expenditure.travel, items: sorted) { claim in
                            ShareRow(title: "\(claim.startDate.formatted(date: .abbreviated, time: .omitted)) - \(claim.endDate.formatted(date: .abbreviated, time: .omitted))", subtitle: nil, date: nil, amount: claim.total)
                        }
                    },
                    tapAction: {
                        viewModel.handleHeaderTap(isCollapsed: $viewModel.travelCollapsed, firstItemId: "travel-first", proxy: proxy, reduceMotion: reduceMotion)
                    }
                )) {
                    if !viewModel.travelCollapsed {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("travel-first")
                            .onAppear { viewModel.visibleIds.insert("travel-first") }
                            .onDisappear { viewModel.visibleIds.remove("travel-first") }

                        if viewModel.sortedTravelClaims(for: expenditure).isEmpty && !viewModel.isLoading {
                            Text("No detailed travel records found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.sortedTravelClaims(for: expenditure)) { claim in
                                TravelClaimRow(claim: claim)
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            item = viewModel.shareCell(TravelClaimRow(claim: claim))
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.accentColor)
                                    }
                            }
                        }
                    }
                }

                Section(header: SectionHeader(
                    title: "Hospitality",
                    total: expenditure.hospitality,
                    isCollapsed: viewModel.hospitalityCollapsed,
                    shareAction: {
                        let sorted = expenditure.hospitalityDetails.sorted { $0.total > $1.total }
                        item = viewModel.shareSection(expenditure: expenditure, category: "Hospitality", total: expenditure.hospitality, items: sorted) { h in
                            let subtitle = h.typeOfEvent.isEmpty ? h.purposeOfHospitality : "\(h.typeOfEvent): \(h.purposeOfHospitality)"
                            ShareRow(title: h.supplier, subtitle: subtitle, date: h.date.formatted(date: .abbreviated, time: .omitted), amount: h.total)
                        }
                    },
                    tapAction: {
                        viewModel.handleHeaderTap(isCollapsed: $viewModel.hospitalityCollapsed, firstItemId: "hospitality-first", proxy: proxy, reduceMotion: reduceMotion)
                    }
                )) {
                    if !viewModel.hospitalityCollapsed {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("hospitality-first")
                            .onAppear { viewModel.visibleIds.insert("hospitality-first") }
                            .onDisappear { viewModel.visibleIds.remove("hospitality-first") }

                        if viewModel.sortedHospitalityDetails(for: expenditure).isEmpty && !viewModel.isLoading {
                            Text("No detailed hospitality records found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.sortedHospitalityDetails(for: expenditure)) { h in
                                let row = HospitalityRow(item: h)
                                row
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            item = viewModel.shareCell(row)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.accentColor)
                                    }
                            }
                        }
                    }
                }

                Section(header: SectionHeader(
                    title: "Contracts",
                    total: expenditure.contracts,
                    isCollapsed: viewModel.contractsCollapsed,
                    shareAction: {
                        let sorted = expenditure.contractDetails.sorted { $0.total > $1.total }
                        item = viewModel.shareSection(expenditure: expenditure, category: "Contracts", total: expenditure.contracts, items: sorted) { c in
                            ShareRow(title: c.supplier, subtitle: c.details, date: c.date.formatted(date: .abbreviated, time: .omitted), amount: c.total)
                        }
                    },
                    tapAction: {
                        viewModel.handleHeaderTap(isCollapsed: $viewModel.contractsCollapsed, firstItemId: "contracts-first", proxy: proxy, reduceMotion: reduceMotion)
                    }
                )) {
                    if !viewModel.contractsCollapsed {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("contracts-first")
                            .onAppear { viewModel.visibleIds.insert("contracts-first") }
                            .onDisappear { viewModel.visibleIds.remove("contracts-first") }

                        if viewModel.sortedContractDetails(for: expenditure).isEmpty && !viewModel.isLoading {
                            Text("No detailed contract records found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.sortedContractDetails(for: expenditure)) { c in
                                let row = ContractRow(item: c)
                                row
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            item = viewModel.shareCell(row)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.accentColor)
                                    }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .adaptiveReadingWidth()
            .navigationTitle("\(expenditure.firstName) \(expenditure.lastName) (\(String(expenditure.year)) Q\(expenditure.quarter))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            item = viewModel.shareSummary(expenditure: expenditure)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }

                        Menu {
                            Picker("Sort By", selection: $viewModel.sortOption) {
                                ForEach(ExpenditureDetailViewModel.SortOption.allCases) { option in
                                    Text(LocalizedStringKey(option.rawValue)).tag(option)
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .activitySheet($item)
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Fetching details...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(ExpenditureDetailLayout.loadingCornerRadius)
                }
            }
            .task {
                await viewModel.loadDetails(expenditure: expenditure, fetch: fetch)
            }
        }
    }
}

struct SummarySection: View {
    let title: LocalizedStringKey
    let total: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(total.formatted(.currency(code: "CAD")))
        }
        .font(.subheadline)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    let total: Double
    let isCollapsed: Bool
    let shareAction: () -> Void
    let tapAction: () -> Void
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : ExpenditureDetailLayout.expandedRotationDegrees))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                (Text(title) + Text(" – Total: \(total.formatted(.currency(code: "CAD")))"))
                    .font(.headline)
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: tapAction)
            
            Button(action: shareAction) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .textCase(nil)
            }
        }
        .padding(.vertical, ExpenditureDetailLayout.headerVerticalPadding)
        .padding(.horizontal)
        .glassHeaderStyle()
        .listRowInsets(EdgeInsets())
    }
}

struct ShareRow: View {
    let title: String
    let subtitle: String?
    let date: String?
    let amount: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: ExpenditureDetailLayout.rowTextSpacing) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(amount.formatted(.currency(code: "CAD")))
                    .font(.subheadline)
            }
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let date = date {
                Text(date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(.black)
    }
}

struct HospitalityRow: View {
    let item: HospitalityExpenditure
    
    var body: some View {
        VStack(alignment: .leading, spacing: ExpenditureDetailLayout.rowTextSpacing) {
            HStack {
                Text(item.supplier)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(item.total.formatted(.currency(code: "CAD")))
                    .font(.subheadline)
            }
            
            Text(item.typeOfEvent.isEmpty ? item.purposeOfHospitality : "\(item.typeOfEvent): \(item.purposeOfHospitality)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                if item.totalOfAttendees > 0 {
                    Text("•")
                    Text("\(item.totalOfAttendees) \(item.totalOfAttendees == 1 ? "attendee" : "attendees")")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, ExpenditureDetailLayout.rowVerticalPadding)
    }
}

struct ContractRow: View {
    let item: ContractExpenditure
    
    var body: some View {
        VStack(alignment: .leading, spacing: ExpenditureDetailLayout.rowTextSpacing) {
            HStack {
                Text(item.supplier)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(item.total.formatted(.currency(code: "CAD")))
                    .font(.subheadline)
            }
            Text(item.details)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, ExpenditureDetailLayout.rowVerticalPadding)
    }
}

struct TravelClaimRow: View {
    let claim: TravelClaim
    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(claim: TravelClaim, initiallyExpanded: Bool = false) {
        self.claim = claim
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(claim.startDate.formatted(date: .abbreviated, time: .omitted)) - \(claim.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(claim.total.formatted(.currency(code: "CAD")))
                    .font(.body).fontWeight(.semibold)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? nil : .snappy) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                ForEach(claim.details) { detail in
                    VStack(alignment: .leading, spacing: ExpenditureDetailLayout.rowDetailSpacing) {
                        Text(detail.purposeOfTravel)
                            .fontWeight(.medium)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                Text(detail.travellerName ?? "")
                                Text(detail.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                            }
                            Spacer()
                            if detail.departure == detail.destination {
                                Text(detail.departure)
                            } else {
                                Text("\(detail.departure) -> \(detail.destination)")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.leading)
                    .padding(.vertical, ExpenditureDetailLayout.rowVerticalPadding)
                }
            }
        }
        .padding(.vertical, ExpenditureDetailLayout.rowVerticalPadding)
    }
}
