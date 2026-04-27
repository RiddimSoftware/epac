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

    @State private var viewModel = ExpendituresViewModel()
    @State private var item: ActivityItem?

    private var filteredExpenditures: [SummaryExpenditure] {
        viewModel.filteredExpenditures(from: expenditures)
    }

    var body: some View {
        ZStack {
                if filteredExpenditures.isEmpty && viewModel.isLoading {
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
                } else if viewModel.loadFailed && filteredExpenditures.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Load Expenditures", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") {
                            Task {
                                await viewModel.loadData(expenditures: Array(expenditures), fetch: fetch)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if filteredExpenditures.isEmpty && !viewModel.isLoading {
                            ContentUnavailableView.search(text: viewModel.searchText)
                        } else {
                            ForEach(filteredExpenditures) { expenditure in
                                let member = members.first { $0.firstName == expenditure.firstName && $0.lastName == expenditure.lastName }
                                NavigationLink(destination: ExpenditureDetailView(expenditure: expenditure)) {
                                    ExpenditureRow(expenditure: expenditure, member: member)
                                }
                            }
                        }
                    }
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
                        NavigationLink(destination: PoliticalDonationsView()) {
                            Image(systemName: "dollarsign.circle")
                        }
                        .accessibilityLabel("Political Donations")
                        NavigationLink(destination: FederalProjectCostView()) {
                            Image(systemName: "building.2.crop.circle")
                        }
                        .accessibilityLabel("Federal Project Costs")
                        sortSelector
                        Button {
                            item = viewModel.shareExpenditures(expenditures: filteredExpenditures, members: Array(members))
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .activitySheet($item)
            .task(id: viewModel.selectedYear * 10 + viewModel.selectedQuarter) {
                await viewModel.loadData(expenditures: Array(expenditures), fetch: fetch)
            }
            .onAppear {
                Log.debug("ExpendituresView appeared. Query count: \(expenditures.count)")
            }
            .onChange(of: expenditures) { oldValue, newValue in
                Log.debug("Expenditures query updated. New count: \(newValue.count)")
            }
    }

    private var periodSelector: some View {
        Menu {
            Picker("Period", selection: Binding(
                get: { ExpendituresViewModel.ExpenditurePeriod(year: viewModel.selectedYear, quarter: viewModel.selectedQuarter) },
                set: {
                    viewModel.selectedYear = $0.year
                    viewModel.selectedQuarter = $0.quarter
                }
            )) {
                ForEach(viewModel.periods) { period in
                    Text("\(String(period.year)) Q\(period.quarter)").tag(period)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(String(viewModel.selectedYear)) Q\(viewModel.selectedQuarter)")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .fontWeight(.medium)
        }
    }

    private var sortSelector: some View {
        Menu {
            Picker("Sort By", selection: $viewModel.sortOrder) {
                ForEach(ExpendituresViewModel.SortOrder.allCases) { order in
                    Text(LocalizedStringKey(order.rawValue)).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var searchBar: some View {
        HStack {
            TextField("Search for a member", text: $viewModel.searchText)
                .padding(7)
                .padding(.horizontal, 25)
                .background(Color.clear)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)

                        if !viewModel.searchText.isEmpty {
                            Button(action: {
                                viewModel.searchText = ""
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
                        .fill(Color.party(expenditure.party).opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(expenditure.firstName.prefix(1) + expenditure.lastName.prefix(1))
                                .font(.headline)
                                .foregroundColor(Color.party(expenditure.party))
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
