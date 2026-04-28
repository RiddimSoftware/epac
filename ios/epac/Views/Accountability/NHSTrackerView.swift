//
//  NHSTrackerView.swift
//  epac
//

import SwiftUI

struct NHSTrackerView: View {
    @Environment(\.openURL) private var openURL

    private let db = NHSProgressDatabase.self

    var body: some View {
        List {
            Section {
                overallProgressCard
            }

            Section {
                ForEach(db.yearlyProgress) { yr in
                    yearRow(yr)
                }
            } header: {
                Text("Year-over-Year")
            } footer: {
                Text("Cumulative homes committed under ACLP, NCIF, RHI, and Innovation Fund. Source: CMHC NHS Annual Progress Reports.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            programSection(title: "Construction Programs", category: .newConstruction)
            programSection(title: "Repair & Retrofit", category: .repair)
            programSection(title: "Direct Financial Support", category: .directBenefit)
            programSection(title: "Enabling Programs", category: .enabling)

            Section {
                Button {
                    openURL(db.progressReportURL)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NHS Quarterly Progress Report (Q1 2024)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("Federal targets vs. units delivered (PDF)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Button {
                    openURL(db.sourceURL)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "house.lodge.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("National Housing Strategy Overview")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("CMHC — cmhc-schl.gc.ca")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Data: \(db.dataSource). Reporting period: \(db.reportingPeriod). Program budgets are federal commitments; some programs are jointly funded with provinces.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("NHS Tracker")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sub-views

    private var overallProgressCard: some View {
        let committed = db.totalCommitted
        let target    = db.totalHomesTarget
        let fraction  = min(Double(committed) / Double(target), 1.0)
        let remaining = target - committed

        return VStack(alignment: .leading, spacing: 12) {
            Text("National Housing Strategy")
                .font(.headline)
            Text("10-year federal plan (2017–2027) · \(db.reportingPeriod)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(.orange)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(committed.formatted()) homes")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("committed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(target.formatted()) homes")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("target (new + repaired)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(format: "%.0f%% of target committed — %dK homes remaining", fraction * 100, remaining / 1000))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func yearRow(_ yr: NHSYearlyProgress) -> some View {
        let maxCommitted = db.yearlyProgress.map(\.cumulativeHomesCommitted).max() ?? 1
        let fraction = Double(yr.cumulativeHomesCommitted) / Double(maxCommitted)

        return HStack(spacing: 12) {
            Text("FY \(yr.fiscalYearEnd - 1)–\(String(yr.fiscalYearEnd).suffix(2))")
                .font(.caption.monospacedDigit())
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.orange.opacity(0.25))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * fraction)
                    }
            }
            .frame(height: 10)
            Text("\(yr.cumulativeHomesCommitted.formatted())")
                .font(.caption.monospacedDigit())
                .frame(width: 68, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func programSection(title: String, category: NHSCategory) -> some View {
        let filtered = db.programs.filter { $0.category == category }
        if !filtered.isEmpty {
            Section(title) {
                ForEach(filtered) { program in
                    programRow(program)
                }
            }
        }
    }

    private func programRow(_ program: NHSProgram) -> some View {
        let fraction = min(Double(program.committedUnits) / Double(program.targetUnits), 1.0)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(program.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("$\(program.budgetBillions, specifier: "%.1f")B")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(tint(for: program.category))

            HStack {
                Text("\(program.committedUnits.formatted()) \(program.unitLabel) committed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("of \(program.targetUnits.formatted())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func tint(for category: NHSCategory) -> Color {
        switch category {
        case .newConstruction: return .orange
        case .repair:          return .brown
        case .directBenefit:   return .green
        case .enabling:        return .teal
        }
    }
}
