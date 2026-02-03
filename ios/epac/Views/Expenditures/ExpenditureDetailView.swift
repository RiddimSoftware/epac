//
//  ExpenditureDetailView.swift
//  epac
//
//  Created by Sunny on 2026-01-29.
//

import SwiftUI
import SwiftData
import ActivityView

struct ExpenditureDetailView: View {
    let expenditure: SummaryExpenditure
    @EnvironmentObject var fetch: Fetch
    
    @State private var isLoading = false
    @State private var sortOption: SortOption = .date
    @State private var item: ActivityItem?
    
    @State private var travelCollapsed = false
    @State private var hospitalityCollapsed = false
    @State private var contractsCollapsed = false
    @State private var visibleIds: Set<String> = []
    
    enum SortOption: String, CaseIterable, Identifiable {
        case date = "Date"
        case amount = "Amount"
        var id: String { rawValue }
    }
    
    private var sortedTravelClaims: [TravelClaim] {
        expenditure.travelClaims.sorted {
            switch sortOption {
            case .date: return $0.startDate > $1.startDate
            case .amount: return $0.total > $1.total
            }
        }
    }
    
    private var sortedHospitalityDetails: [HospitalityExpenditure] {
        expenditure.hospitalityDetails.sorted {
            switch sortOption {
            case .date: return $0.date > $1.date
            case .amount: return $0.total > $1.total
            }
        }
    }
    
    private var sortedContractDetails: [ContractExpenditure] {
        expenditure.contractDetails.sorted {
            switch sortOption {
            case .date: return $0.date > $1.date
            case .amount: return $0.total > $1.total
            }
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section(header: SectionHeader(
                    title: "Travel",
                    total: expenditure.travel,
                    isCollapsed: travelCollapsed,
                    shareAction: {
                        let sorted = expenditure.travelClaims.sorted { $0.total > $1.total }
                        shareSection(category: "Travel", total: expenditure.travel, items: sorted) { claim in
                            ShareRow(title: "\(claim.startDate.formatted(date: .abbreviated, time: .omitted)) - \(claim.endDate.formatted(date: .abbreviated, time: .omitted))", subtitle: nil, date: nil, amount: claim.total)
                        }
                    },
                    tapAction: {
                        handleHeaderTap(isCollapsed: $travelCollapsed, firstItemId: "travel-first", proxy: proxy)
                    }
                )) {
                    if !travelCollapsed {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("travel-first")
                            .onAppear { visibleIds.insert("travel-first") }
                            .onDisappear { visibleIds.remove("travel-first") }
                        
                        if sortedTravelClaims.isEmpty && !isLoading {
                            Text("No detailed travel records found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(sortedTravelClaims) { claim in
                                TravelClaimRow(claim: claim)
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            shareCell(TravelClaimRow(claim: claim))
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
                    isCollapsed: hospitalityCollapsed,
                    shareAction: {
                        let sorted = expenditure.hospitalityDetails.sorted { $0.total > $1.total }
                        shareSection(category: "Hospitality", total: expenditure.hospitality, items: sorted) { item in
                            let subtitle = item.typeOfEvent.isEmpty ? item.purposeOfHospitality : "\(item.typeOfEvent): \(item.purposeOfHospitality)"
                            ShareRow(title: item.supplier, subtitle: subtitle, date: item.date.formatted(date: .abbreviated, time: .omitted), amount: item.total)
                        }
                    },
                    tapAction: {
                        handleHeaderTap(isCollapsed: $hospitalityCollapsed, firstItemId: "hospitality-first", proxy: proxy)
                    }
                )) {
                    if !hospitalityCollapsed {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("hospitality-first")
                            .onAppear { visibleIds.insert("hospitality-first") }
                            .onDisappear { visibleIds.remove("hospitality-first") }
                        
                        if sortedHospitalityDetails.isEmpty && !isLoading {
                            Text("No detailed hospitality records found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(sortedHospitalityDetails) { item in
                                let row = HospitalityRow(item: item)
                                row
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            shareCell(row)
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
                    isCollapsed: contractsCollapsed,
                    shareAction: {
                        let sorted = expenditure.contractDetails.sorted { $0.total > $1.total }
                        shareSection(category: "Contracts", total: expenditure.contracts, items: sorted) { item in
                            ShareRow(title: item.supplier, subtitle: item.details, date: item.date.formatted(date: .abbreviated, time: .omitted), amount: item.total)
                        }
                    },
                    tapAction: {
                        handleHeaderTap(isCollapsed: $contractsCollapsed, firstItemId: "contracts-first", proxy: proxy)
                    }
                )) {
                    if !contractsCollapsed {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("contracts-first")
                            .onAppear { visibleIds.insert("contracts-first") }
                            .onDisappear { visibleIds.remove("contracts-first") }
                        
                        if sortedContractDetails.isEmpty && !isLoading {
                            Text("No detailed contract records found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(sortedContractDetails) { item in
                                let row = ContractRow(item: item)
                                row
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            shareCell(row)
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
		            .navigationTitle("\(expenditure.firstName) \(expenditure.lastName) (\(String(expenditure.year)) Q\(expenditure.quarter))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            shareSummary()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                ForEach(SortOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
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
                if isLoading {
                    ProgressView("Fetching details...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }
            }
            .task {
                if expenditure.travelClaims.isEmpty && expenditure.hospitalityDetails.isEmpty && expenditure.contractDetails.isEmpty {
                    isLoading = true
                    do {
                        try await fetch.downloadDetailedExpenditures(identifier: expenditure.id)
                    } catch {
                        Log.error("Failed to download details: \(error.localizedDescription)")
                    }
                    isLoading = false
                }
            }
        }
    }

    private func handleHeaderTap(isCollapsed: Binding<Bool>, firstItemId: String, proxy: ScrollViewProxy) {
        if isCollapsed.wrappedValue {
            withAnimation(.snappy) {
                isCollapsed.wrappedValue = false
            }
        } else {
            if visibleIds.contains(firstItemId) {
                withAnimation(.snappy) {
                    isCollapsed.wrappedValue = true
                }
            } else {
                withAnimation(.snappy) {
                    proxy.scrollTo(firstItemId, anchor: .top)
                }
            }
        }
    }

    @MainActor
    private func shareSummary() {
        let title = "\(expenditure.firstName) \(expenditure.lastName) (\(String(expenditure.year)) Q\(expenditure.quarter))"
        let view = VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 8) {
                SummarySection(title: "Travel", total: expenditure.travel)
                SummarySection(title: "Hospitality", total: expenditure.hospitality)
                SummarySection(title: "Contracts", total: expenditure.contracts)
            }
            .foregroundColor(.black)
            
            Divider()
            
            HStack {
                Text("Total Expenditures")
                    .fontWeight(.bold)
                Spacer()
                Text(expenditure.total.formatted(.currency(code: "CAD")))
                    .fontWeight(.bold)
            }
            .foregroundColor(.black)
        }
        .padding()
        .frame(width: 350)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        
        renderAndShare(view, title: title)
    }

    @MainActor
    private func shareSection<T: Identifiable, V: View>(category: String, total: Double, items: [T], @ViewBuilder rowBuilder: @escaping (T) -> V) {
        let title = "\(expenditure.firstName) \(expenditure.lastName) (\(String(expenditure.year)) Q\(expenditure.quarter))"
        let shareItems = Array(items.prefix(5))
        let moreCount = items.count - shareItems.count
        
        let view = VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                HStack {
                    Text(category)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    Spacer()
                    Text(total.formatted(.currency(code: "CAD")))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shareItems) { item in
                    rowBuilder(item)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.white)
                    Divider()
                }
                
                if moreCount > 0 {
                    Text("... and \(moreCount) more items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(Color.white)
                }
            }
        }
        .frame(width: 400)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        
        renderAndShare(view, title: "\(category) - \(title)")
    }

    @MainActor
    private func shareCell<V: View>(_ view: V) {
        let renderedView = view
            .padding()
            .frame(width: 350)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        
        renderAndShare(renderedView, title: "Expenditure Detail")
    }

    @MainActor
    private func renderAndShare<V: View>(_ view: V, title: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            let source = ShareActivityItemSource(image: image, title: title)
            self.item = ActivityItem(items: source)
        }
    }
}

struct SummarySection: View {
    let title: String
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
    let title: String
    let total: Double
    let isCollapsed: Bool
    let shareAction: () -> Void
    let tapAction: () -> Void
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(title) - Total: \(total.formatted(.currency(code: "CAD")))")
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
        .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 4)
    }
}

struct ContractRow: View {
    let item: ContractExpenditure
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 4)
    }
}

struct TravelClaimRow: View {
    let claim: TravelClaim
    @State private var isExpanded: Bool

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
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                ForEach(claim.details) { detail in
                    VStack(alignment: .leading, spacing: 4) {
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
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
