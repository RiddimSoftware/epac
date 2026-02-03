//
//  ExpendituresView.swift
//  epac
//
//  Created by Sunny on 2026-01-29.
//

import SwiftUI
import SwiftData
import ActivityView

struct ExpendituresView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var fetch: Fetch
    @Query private var expenditures: [SummaryExpenditure]
    @Query private var members: [ParliamentMember]
    
    @State private var selectedYear = 2026
    @State private var selectedQuarter = 2
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .total
    @State private var isLoading = false
    @State private var item: ActivityItem?
    
    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name"
        case total = "Total"
        case travel = "Travel"
        case hospitality = "Hospitality"
        case contracts = "Contracts"
        
        var id: String { rawValue }
    }
    
    struct ExpenditurePeriod: Hashable, Identifiable {
        var id: String { "\(year) Q\(quarter)" }
        let year: Int
        let quarter: Int
    }
    
    private let periods: [ExpenditurePeriod] = {
        var p: [ExpenditurePeriod] = []
        for year in (2021...2026).reversed() {
            for quarter in (1...4).reversed() {
                if (year == 2021 && quarter < 2) || (year == 2026 && quarter > 2) {
                    continue
                }
                p.append(ExpenditurePeriod(year: year, quarter: quarter))
            }
        }
        return p
    }()
    
    private var filteredExpenditures: [SummaryExpenditure] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = expenditures.filter { expenditure in
            expenditure.year == selectedYear && expenditure.quarter == selectedQuarter &&
            (trimmed.isEmpty || 
             expenditure.firstName.lowercased().contains(trimmed) || 
             expenditure.lastName.lowercased().contains(trimmed))
        }
        
        return filtered.sorted { a, b in
            switch sortOrder {
            case .name:
                return a.lastName < b.lastName
            case .total:
                return a.total > b.total
            case .travel:
                return a.travel > b.travel
            case .hospitality:
                return a.hospitality > b.hospitality
            case .contracts:
                return a.contracts > b.contracts
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if filteredExpenditures.isEmpty && isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Fetching expenditure data...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("This may take a moment.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if filteredExpenditures.isEmpty && !isLoading {
                            ContentUnavailableView.search(text: searchText)
                                        } else {
                                            ForEach(filteredExpenditures) { expenditure in
                                                let member = members.first { $0.firstName == expenditure.firstName && $0.lastName == expenditure.lastName }
                                                NavigationLink(destination: ExpenditureDetailView(expenditure: expenditure)) {
                                                    ExpenditureRow(expenditure: expenditure, member: member)
                                                }
                                            }
                                        }                    }
                    .listStyle(.plain)
                }
                
                VStack {
                    Spacer()
                    searchBar
                }
                .padding(.bottom, 10)
            }
            .navigationTitle("Expenditures")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    periodSelector
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        sortSelector
                        Button {
                            shareExpenditures()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .activitySheet($item)
            .task(id: selectedYear * 10 + selectedQuarter) {
                await loadData()
            }
            .onAppear {
                Log.debug("ExpendituresView appeared. Query count: \(expenditures.count)")
            }
            .onChange(of: expenditures) { oldValue, newValue in
                Log.debug("Expenditures query updated. New count: \(newValue.count)")
            }
        }
    }
    
    private var periodSelector: some View {
        Menu {
            Picker("Period", selection: Binding(
                get: { ExpenditurePeriod(year: selectedYear, quarter: selectedQuarter) },
                set: { 
                    selectedYear = $0.year
                    selectedQuarter = $0.quarter
                }
            )) {
                ForEach(periods) { period in
                    Text("\(String(period.year)) Q\(period.quarter)").tag(period)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(String(selectedYear)) Q\(selectedQuarter)")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .fontWeight(.medium)
        }
    }
    
    private var sortSelector: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
    
    private var searchBar: some View {
        HStack {
            TextField("Search for a member", text: $searchText)
                .padding(7)
                .padding(.horizontal, 25)
                .background(Color.clear)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)

                        if !searchText.isEmpty {
                            Button(action: {
                                self.searchText = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 5)
        .glassHeaderStyle()
        .padding(.horizontal)
    }
    
    private func loadData() async {
        let exists = expenditures.contains { $0.year == selectedYear && $0.quarter == selectedQuarter }
        if !exists {
            isLoading = true
            do {
                try await fetch.expenditures(year: selectedYear, quarter: selectedQuarter)
            } catch {
                Log.error("Failed to load expenditures: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    @MainActor
    private func shareExpenditures() {
        let view = VStack(spacing: 0) {
            Text("Expenditures - \(selectedYear) Q\(selectedQuarter)")
                .font(.headline)
                .padding()
            
            ForEach(filteredExpenditures.prefix(20)) { expenditure in
                let member = members.first { $0.firstName == expenditure.firstName && $0.lastName == expenditure.lastName }
                ExpenditureRow(expenditure: expenditure, member: member)
                    .padding()
                Divider()
            }
            
            if filteredExpenditures.count > 20 {
                Text("... and \(filteredExpenditures.count - 20) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .frame(width: 400)
        .background(Color(UIColor.systemBackground))
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            let source = ShareActivityItemSource(image: image, title: "Expenditures - \(selectedYear) Q\(selectedQuarter)")
            self.item = ActivityItem(items: source)
        }
    }
}

struct ExpenditureRow: View {
    let expenditure: SummaryExpenditure
    let member: ParliamentMember?
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let member = member {
                    MemberAvatar(member: member)
                        .frame(width: 44, height: 44)
                } else {
                    Circle()
                        .fill(Color(uiColor: expenditure.party.colour).opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(expenditure.firstName.prefix(1) + expenditure.lastName.prefix(1))
                                .font(.headline)
                                .foregroundColor(Color(uiColor: expenditure.party.colour))
                        )
                }
                
                if let partyImage = expenditure.party.image {
                    Image(uiImage: partyImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .padding(2)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                        .offset(x: 4, y: 4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(expenditure.lastName), \(expenditure.firstName)")
                        .font(.headline)
                    Spacer()
                    Text(expenditure.total.formatted(.currency(code: "CAD")))
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                
                Text(expenditure.constituency)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Travel").font(.caption2).foregroundColor(.secondary)
                        Text(expenditure.travel.formatted(.currency(code: "CAD"))).font(.caption)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Hospitality").font(.caption2).foregroundColor(.secondary)
                        Text(expenditure.hospitality.formatted(.currency(code: "CAD"))).font(.caption)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Contracts").font(.caption2).foregroundColor(.secondary)
                        Text(expenditure.contracts.formatted(.currency(code: "CAD"))).font(.caption)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

//private struct MemberAvatar: View {
//    let member: ParliamentMember
//
//    var body: some View {
//        AsyncImage(url: member.photoURL) { phase in
//            switch phase {
//            case .success(let image):
//                image
//                    .resizable()
//                    .scaledToFill()
//            case .failure:
//                placeholder
//            default:
//                placeholder
//            }
//        }
//        .clipShape(Circle())
//        .overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))
//    }
//
//    private var placeholder: some View {
//        ZStack {
//            Color(uiColor: member.party.colour).opacity(0.2)
//            Text(member.initials)
//                .font(.headline)
//                .foregroundColor(Color(uiColor: member.party.colour))
//        }
//        .background(Color(.systemGray6))
//    }
//}
