//
//  ExpendituresView.swift
//  epac
//
//  Created by Sunny on 2026-01-29.
//

import ActivityView
import SwiftData
import SwiftUI

private enum ExpendituresLayout {
	static let loadingStackSpacing = EpacSpacing.m
	static let loadingScale = 1.5
	static let retryDelaySeconds: Int64 = 2
	static let badgeBottomPadding = EpacSpacing.xs
	static let insetBottomPadding: CGFloat = 10
	static let periodSelectorSpacing = EpacSpacing.xs
	static let taskIDQuarterMultiplier = 10
	static let searchFieldPadding: CGFloat = 7
	static let searchFieldHorizontalPadding: CGFloat = 25
	static let searchIconLeadingPadding = EpacSpacing.s
	static let searchButtonTrailingPadding = EpacSpacing.s
	static let searchBarHorizontalPadding: CGFloat = 10
	static let searchBarVerticalPadding: CGFloat = 5
	static let listColumnMinWidth: CGFloat = 320
	static let listColumnIdealWidth: CGFloat = 360
	static let listColumnMaxWidth: CGFloat = 420
	static let selectedRowOpacity = 0.12
	static let rowSpacing: CGFloat = 12
	static let avatarSize: CGFloat = 44
	static let avatarTintOpacity = EpacOpacity.tintStrong
	static let partyBadgeSize: CGFloat = 14
	static let partyBadgePadding = EpacSpacing.xxs
	static let partyBadgeBorderOpacity = EpacOpacity.tintStrong
	static let partyBadgeBorderWidth: CGFloat = 0.5
	static let partyBadgeOffset = EpacSpacing.xs
	static let primaryTextSpacing = EpacSpacing.xs
	static let compactTextSpacing = EpacSpacing.xxs
	static let metricStackSpacing = EpacSpacing.xs
	static let rowVerticalPadding = EpacSpacing.xs
}

struct ExpendituresView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var fetch: Fetch
    @Query private var expenditures: [SummaryExpenditure]
    @Query private var members: [ParliamentMember]

    @Binding private var selectedExpenditure: SummaryExpenditure?
    @State private var viewModel = ExpendituresViewModel()
    @State private var item: ActivityItem?
    @State private var isRetryDisabled = false

    init(selection: Binding<SummaryExpenditure?> = .constant(nil)) {
        self._selectedExpenditure = selection
    }

    private var filteredExpenditures: [SummaryExpenditure] {
        viewModel.filteredExpenditures(from: expenditures)
    }

    private var usesTwoPaneLayout: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    private var visibleSelectedExpenditure: SummaryExpenditure? {
        ExpendituresSelectionPolicy.retainedSelection(selectedExpenditure, visibleExpenditures: filteredExpenditures)
    }

    var body: some View {
        Group {
            if usesTwoPaneLayout {
                regularLayout
            } else {
                compactLayout
            }
        }
        .activitySheet($item)
        .task(id: viewModel.selectedYear * ExpendituresLayout.taskIDQuarterMultiplier + viewModel.selectedQuarter) {
            await viewModel.loadData(expenditures: Array(expenditures), fetch: fetch)
        }
        .onAppear {
            Log.debug("ExpendituresView appeared. Query count: \(expenditures.count)")
            reconcileSelection()
        }
        .onChange(of: expenditures) { _, newValue in
            Log.debug("Expenditures query updated. New count: \(newValue.count)")
            reconcileSelection()
        }
        .onChange(of: viewModel.searchText) {
            reconcileSelection()
        }
        .onChange(of: viewModel.selectedYear) {
            reconcileSelection()
        }
        .onChange(of: viewModel.selectedQuarter) {
            reconcileSelection()
        }
        .onChange(of: viewModel.sortOrder) {
            reconcileSelection()
        }
    }

    private var compactLayout: some View {
        expenditureList(rowContent: compactRow)
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh(fetch: fetch)
            }
            .listBottomChrome(searchBar: searchBar)
            .navigationTitle("Expenditures")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            expenditureList(rowContent: regularRow)
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refresh(fetch: fetch)
                }
                .listBottomChrome(searchBar: searchBar)
                .navigationTitle("Expenditures")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .navigationSplitViewColumnWidth(
                    min: ExpendituresLayout.listColumnMinWidth,
                    ideal: ExpendituresLayout.listColumnIdealWidth,
                    max: ExpendituresLayout.listColumnMaxWidth
                )
        } detail: {
            if let expenditure = visibleSelectedExpenditure {
                ExpenditureDetailView(expenditure: expenditure)
            } else {
                Text("expenditures.detail.placeholder")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func expenditureList<RowContent: View>(
        @ViewBuilder rowContent: @escaping (SummaryExpenditure, ParliamentMember?) -> RowContent
    ) -> some View {
        Group {
            if filteredExpenditures.isEmpty && viewModel.isLoading {
                VStack(spacing: ExpendituresLayout.loadingStackSpacing) {
                    ProgressView()
                        .scaleEffect(ExpendituresLayout.loadingScale)
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
                        guard !isRetryDisabled else { return }
                        isRetryDisabled = true
                        Task { try? await Task.sleep(for: .seconds(ExpendituresLayout.retryDelaySeconds)); isRetryDisabled = false }
                        Task { await viewModel.loadData(expenditures: Array(expenditures), fetch: fetch) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetryDisabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if filteredExpenditures.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else {
                        ForEach(filteredExpenditures) { expenditure in
                            let member = members.first { $0.firstName == expenditure.firstName && $0.lastName == expenditure.lastName }
                            rowContent(expenditure, member)
                        }
                    }
                }
            }
        }
    }

    private func compactRow(expenditure: SummaryExpenditure, member: ParliamentMember?) -> some View {
        NavigationLink(destination: ExpenditureDetailView(expenditure: expenditure)) {
            ExpenditureRow(expenditure: expenditure, member: member)
        }
    }

    private func regularRow(expenditure: SummaryExpenditure, member: ParliamentMember?) -> some View {
        Button {
            selectedExpenditure = expenditure
        } label: {
            ExpenditureRow(expenditure: expenditure, member: member)
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground(for: expenditure))
        .accessibilityAddTraits(isSelected(expenditure) ? [.isSelected] : [])
    }

    private func rowBackground(for expenditure: SummaryExpenditure) -> Color {
        isSelected(expenditure) ? Color.accentColor.opacity(ExpendituresLayout.selectedRowOpacity) : Color.clear
    }

    private func isSelected(_ expenditure: SummaryExpenditure) -> Bool {
        visibleSelectedExpenditure?.persistentModelID == expenditure.persistentModelID
    }

    private func reconcileSelection() {
        selectedExpenditure = visibleSelectedExpenditure
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                NavigationLink(destination: FederalFinancesView()) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .accessibilityLabel("Federal Finances")
                sortSelector
                Button {
                    item = viewModel.shareExpenditures(expenditures: filteredExpenditures, members: Array(members))
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
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
            HStack(spacing: ExpendituresLayout.periodSelectorSpacing) {
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
                .padding(ExpendituresLayout.searchFieldPadding)
                .padding(.horizontal, ExpendituresLayout.searchFieldHorizontalPadding)
                .background(Color.clear)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, ExpendituresLayout.searchIconLeadingPadding)

                        if !viewModel.searchText.isEmpty {
                            Button(action: {
                                viewModel.searchText = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, ExpendituresLayout.searchButtonTrailingPadding)
                            }
                        }
                    }
                )
                .padding(.horizontal, ExpendituresLayout.searchBarHorizontalPadding)
        }
        .padding(.vertical, ExpendituresLayout.searchBarVerticalPadding)
        .glassHeaderStyle()
        .padding(.horizontal)
    }
}

enum ExpendituresSelectionPolicy {
    static func retainedSelection(
        _ selection: SummaryExpenditure?,
        visibleExpenditures: [SummaryExpenditure]
    ) -> SummaryExpenditure? {
        guard let selection else { return nil }
        return visibleExpenditures.first { $0.persistentModelID == selection.persistentModelID }
    }
}

private extension View {
    func listBottomChrome(searchBar: some View) -> some View {
        safeAreaInset(edge: .bottom) {
            VStack {
                HStack {
                    Spacer()
                    DataSourceBadge(source: .expenditures())
                }
                .padding(.horizontal)
                .padding(.bottom, ExpendituresLayout.badgeBottomPadding)
                searchBar
            }
            .padding(.bottom, ExpendituresLayout.insetBottomPadding)
        }
    }
}

struct ExpenditureRow: View {
    let expenditure: SummaryExpenditure
    let member: ParliamentMember?

    var body: some View {
        HStack(spacing: ExpendituresLayout.rowSpacing) {
            ZStack(alignment: .bottomTrailing) {
                if let member = member {
                    MemberAvatar(member: member)
                        .frame(width: ExpendituresLayout.avatarSize, height: ExpendituresLayout.avatarSize)
                } else {
                    Circle()
                        .fill(Color.party(expenditure.party).opacity(ExpendituresLayout.avatarTintOpacity))
                        .frame(width: ExpendituresLayout.avatarSize, height: ExpendituresLayout.avatarSize)
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
                        .frame(width: ExpendituresLayout.partyBadgeSize, height: ExpendituresLayout.partyBadgeSize)
                        .padding(ExpendituresLayout.partyBadgePadding)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(ExpendituresLayout.partyBadgeBorderOpacity), lineWidth: ExpendituresLayout.partyBadgeBorderWidth))
                        .offset(x: ExpendituresLayout.partyBadgeOffset, y: ExpendituresLayout.partyBadgeOffset)
                }
            }

            VStack(alignment: .leading, spacing: ExpendituresLayout.primaryTextSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        memberName
                        Spacer()
                        expenditureTotal
                    }
                    VStack(alignment: .leading, spacing: ExpendituresLayout.compactTextSpacing) {
                        memberName
                        expenditureTotal
                    }
                }

                Text(expenditure.constituency)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        expenditureMetric(label: "Travel", amount: expenditure.travel)
                        Spacer()
                        expenditureMetric(label: "Hospitality", amount: expenditure.hospitality)
                        Spacer()
                        expenditureMetric(label: "Contracts", amount: expenditure.contracts)
                    }
                    VStack(alignment: .leading, spacing: ExpendituresLayout.metricStackSpacing) {
                        expenditureMetric(label: "Travel", amount: expenditure.travel)
                        expenditureMetric(label: "Hospitality", amount: expenditure.hospitality)
                        expenditureMetric(label: "Contracts", amount: expenditure.contracts)
                    }
                }
                .padding(.top, ExpendituresLayout.rowVerticalPadding)
            }
        }
        .padding(.vertical, ExpendituresLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(expenditure.lastName), \(expenditure.firstName), \(expenditure.party.fullName), \(expenditure.constituency), total \(expenditure.total.formatted(.currency(code: "CAD")))")
    }

    private var memberName: some View {
        Text("\(expenditure.lastName), \(expenditure.firstName)")
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var expenditureTotal: some View {
        Text(expenditure.total.formatted(.currency(code: "CAD")))
            .font(.headline)
            .foregroundColor(.accentColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func expenditureMetric(label: String, amount: Double) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(amount.formatted(.currency(code: "CAD")))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// private struct MemberAvatar: View {
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
// }
