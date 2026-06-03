//
//  MinisterialExpensesSectionView.swift
//  epac
//

import SwiftData
import SwiftUI

private enum MinisterialExpensesLayout {
    static let sectionSpacing: CGFloat = 12
    static let rowSpacing = EpacSpacing.xs
    static let rowVerticalPadding = EpacSpacing.xs
    static let cardCornerRadius = EpacCornerRadius.m
    static let bandHeight: CGFloat = 4
    static let summaryRowSpacing = EpacSpacing.s
    static let itemLineLimit = 2
    static let previewLimit = 5
    static let topDestinationsLimit = 3
    static let citationLineLimit = 1
    static let comparisonSpacing: CGFloat = 12
}

// Amber/orange accent distinguishes ministerial-role expenses from the
// party-coloured MP office expenses (EPAC-43) on the same profile.
private let ministerialAccent = Color.appWarning

// MARK: - Section root

struct MinisterialExpensesSectionView: View {
    let ministerName: String
    let memberFirstName: String
    let memberLastName: String

    @Query private var records: [MinisterialExpenseRecord]
    // Most recent MP office expense for side-by-side comparison.
    @Query private var officeSummaries: [SummaryExpenditure]
    @State private var isExpanded = false
    @State private var selectedQuarter: Int? = nil
    @State private var selectedDepartment: String? = nil

    init(ministerName: String, member: ParliamentMember) {
        self.ministerName = ministerName
        self.memberFirstName = member.firstName
        self.memberLastName = member.lastName
        _records = Query(
            filter: #Predicate<MinisterialExpenseRecord> { $0.ministerName == ministerName },
            sort: [SortDescriptor(\MinisterialExpenseRecord.startDate, order: .reverse)]
        )
        let fn = member.firstName
        let ln = member.lastName
        _officeSummaries = Query(
            filter: #Predicate<SummaryExpenditure> { $0.firstName == fn && $0.lastName == ln },
            sort: [SortDescriptor(\SummaryExpenditure.year, order: .reverse),
                   SortDescriptor(\SummaryExpenditure.quarter, order: .reverse)]
        )
    }

    private var latestOfficeSummary: SummaryExpenditure? { officeSummaries.first }

    // Current fiscal year derived from calendar: April start per Government of Canada.
    private var currentFiscalYear: String {
        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        let fiscalStart = month >= 4 ? year : year - 1
        return "\(fiscalStart)-\(fiscalStart + 1)"
    }

    private var currentFiscalYearRecords: [MinisterialExpenseRecord] {
        records.filter { $0.fiscalYear == currentFiscalYear }
    }

    private var filteredRecords: [MinisterialExpenseRecord] {
        records.filter { record in
            (selectedQuarter == nil || record.quarter == selectedQuarter) &&
            (selectedDepartment == nil || record.department == selectedDepartment)
        }
    }

    private var totalThisFiscalYear: Double {
        currentFiscalYearRecords.reduce(0) { $0 + $1.totalCost }
    }

    private var topDestinations: [MinisterialExpenseRecord] {
        Array(currentFiscalYearRecords.sorted { $0.totalCost > $1.totalCost }.prefix(MinisterialExpensesLayout.topDestinationsLimit))
    }

    private var availableQuarters: [Int] {
        Array(Set(records.map(\.quarter))).sorted()
    }

    private var availableDepartments: [String] {
        Array(Set(records.map(\.department))).sorted()
    }

    var body: some View {
        if !records.isEmpty {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: { content },
                label: { label }
            )
            .padding()
            .background(Color.appSurface)
            .cornerRadius(MinisterialExpensesLayout.cardCornerRadius)
            .accessibilityIdentifier("ministerial-expenses-section")
        }
    }

    private var label: some View {
        HStack(spacing: EpacSpacing.s) {
            Image(systemName: "airplane.departure")
                .foregroundStyle(ministerialAccent)
            VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                Text("Ministerial Expenses")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Ministerial role expense")
                    .font(.caption2)
                    .foregroundStyle(ministerialAccent)
            }
            Spacer()
            Text(totalThisFiscalYear, format: .currency(code: "CAD").precision(.fractionLength(0)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: MinisterialExpensesLayout.sectionSpacing) {
            // Amber colour band signals "ministerial role" distinct from MP office expenses.
            ministerialBand

            summaryCard

            if latestOfficeSummary != nil {
                comparisonRow
            }

            filterControls

            Divider()

            recordsList
        }
        .padding(.top, EpacSpacing.s)
    }

    private var ministerialBand: some View {
        Rectangle()
            .fill(ministerialAccent.opacity(0.25))
            .frame(maxWidth: .infinity)
            .frame(height: MinisterialExpensesLayout.bandHeight)
            .overlay(
                Text("Treasury Board Secretariat Proactive Disclosure")
                    .font(.caption2)
                    .foregroundStyle(ministerialAccent)
                    .padding(.horizontal, EpacSpacing.s),
                alignment: .leading
            )
            .cornerRadius(EpacCornerRadius.xs)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                    Text("This fiscal year (\(currentFiscalYear))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalThisFiscalYear, format: .currency(code: "CAD"))
                        .font(.title3.bold())
                        .foregroundStyle(ministerialAccent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: EpacSpacing.xxs) {
                    Text("\(currentFiscalYearRecords.count)")
                        .font(.title3.bold())
                    Text("events disclosed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !topDestinations.isEmpty {
                Divider()
                Text("Top events by cost")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(topDestinations) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                            Text(record.destination)
                                .font(.caption)
                                .lineLimit(MinisterialExpensesLayout.itemLineLimit)
                            Text(record.eventPurpose)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(MinisterialExpensesLayout.itemLineLimit)
                        }
                        Spacer()
                        Text(record.totalCost, format: .currency(code: "CAD"))
                            .font(.caption.bold())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var comparisonRow: some View {
        if let office = latestOfficeSummary {
            VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                Text("Expenses comparison — most recent quarter")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(spacing: MinisterialExpensesLayout.comparisonSpacing) {
                    comparisonCell(
                        label: "Ministerial duties",
                        amount: totalThisFiscalYear,
                        color: ministerialAccent
                    )
                    Divider().frame(height: 40)
                    comparisonCell(
                        label: "MP office",
                        amount: office.total,
                        color: Color.party(office.party)
                    )
                }
            }
            .padding(EpacSpacing.s)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(EpacCornerRadius.s)
        }
    }

    private func comparisonCell(label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .center, spacing: EpacSpacing.xxs) {
            Text(amount, format: .currency(code: "CAD").precision(.fractionLength(0)))
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var filterControls: some View {
        if availableQuarters.count > 1 || availableDepartments.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: EpacSpacing.s) {
                    if availableQuarters.count > 1 {
                        Menu {
                            Button("All quarters") { selectedQuarter = nil }
                            ForEach(availableQuarters, id: \.self) { q in
                                Button("Q\(q)") { selectedQuarter = q }
                            }
                        } label: {
                            filterChip(
                                label: selectedQuarter.map { "Q\($0)" } ?? "Quarter",
                                isActive: selectedQuarter != nil
                            )
                        }
                    }
                    if availableDepartments.count > 1 {
                        Menu {
                            Button("All departments") { selectedDepartment = nil }
                            ForEach(availableDepartments, id: \.self) { dept in
                                Button(dept) { selectedDepartment = dept }
                            }
                        } label: {
                            filterChip(
                                label: selectedDepartment ?? "Department",
                                isActive: selectedDepartment != nil
                            )
                        }
                    }
                }
                .padding(.horizontal, EpacSpacing.xs)
            }
        }
    }

    private func filterChip(label: String, isActive: Bool) -> some View {
        HStack(spacing: EpacSpacing.xxs) {
            Text(label)
                .font(.caption)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, EpacSpacing.s)
        .padding(.vertical, EpacSpacing.xxs)
        .foregroundStyle(isActive ? ministerialAccent : .secondary)
        .background(isActive ? ministerialAccent.opacity(0.12) : Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: MinisterialExpensesLayout.rowSpacing) {
            let displayed = filteredRecords.prefix(MinisterialExpensesLayout.previewLimit)
            ForEach(Array(displayed)) { record in
                MinisterialExpenseRow(record: record)
            }
            if filteredRecords.count > MinisterialExpensesLayout.previewLimit {
                Text("\(filteredRecords.count - MinisterialExpensesLayout.previewLimit) more records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, EpacSpacing.xs)
            }
        }
    }
}

// MARK: - Record row

struct MinisterialExpenseRow: View {
    let record: MinisterialExpenseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                    Text(record.destination)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(record.eventPurpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(MinisterialExpensesLayout.itemLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                    dateRange
                }
                Spacer()
                Text(record.totalCost, format: .currency(code: "CAD"))
                    .font(.caption.bold())
                    .foregroundStyle(ministerialAccent)
            }
            citation
        }
        .padding(.vertical, MinisterialExpensesLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    @ViewBuilder
    private var dateRange: some View {
        let start = record.startDate.formatted(date: .abbreviated, time: .omitted)
        if let end = record.endDate {
            let endStr = end.formatted(date: .abbreviated, time: .omitted)
            Text("\(start) – \(endStr)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text(start)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var citation: some View {
        Group {
            if let url = URL(string: record.sourceURL) {
                Link(destination: url) {
                    citationLabel
                }
                .foregroundStyle(.secondary)
            } else {
                citationLabel
            }
        }
    }

    private var citationLabel: some View {
        HStack(spacing: EpacSpacing.xxs) {
            Image(systemName: "link")
                .font(.caption2)
            Text("Treasury Board Secretariat Proactive Disclosure — \(record.department)")
                .font(.caption2)
                .lineLimit(MinisterialExpensesLayout.citationLineLimit)
        }
        .foregroundStyle(.tertiary)
    }

    private var rowAccessibilityLabel: String {
        let cost = record.totalCost.formatted(.currency(code: "CAD"))
        return "\(record.destination), \(record.eventPurpose), \(cost), \(record.department)"
    }
}
