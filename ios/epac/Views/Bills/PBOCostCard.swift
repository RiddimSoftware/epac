//
//  PBOCostCard.swift
//  epac
//
//  Created on 2026-04-27.
//
//  A self-contained card that surfaces PBO Legislative Costing Notes inside BillDetailView.
//  Card is absent (not broken) when no PBO report exists for the bill.
//

import SwiftUI

struct PBOCostCard: View {
    let bill: Bill

    @State private var reports: [PBOReport] = []
    @State private var isLoading = false

    private enum Layout {
        static let reportPreviewLimit = 2
        static let titleLineLimit = 2
        static let summaryLineLimit = 3
    }

    var body: some View {
        Group {
            if isLoading {
                // Show nothing while loading — avoid flashing a spinner inside the bill detail
                EmptyView()
            } else if !reports.isEmpty {
                costSection
            }
            // If no reports found, show nothing (acceptance criteria: "card absent, not broken")
        }
        .task(id: bill.number) { await load() }
    }

    // MARK: - Cost section

    private var costSection: some View {
        Section(
            header: Text(NSLocalizedString("pbo.sectionTitle", comment: "Section header for PBO cost analysis"))
        ) {
            ForEach(reports.prefix(Layout.reportPreviewLimit)) { report in
                reportRow(report)
            }
        }
    }

    @ViewBuilder
    private func reportRow(_ report: PBOReport) -> some View {
        VStack(alignment: .leading, spacing: EpacSpacing.s) {
            Text(report.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(Layout.titleLineLimit)
                .accessibilityAddTraits(.isHeader)

            if let date = report.reportDate {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !report.summary.isEmpty {
                Text(report.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(Layout.summaryLineLimit)
            }

            if let pbo = report.pboEstimate {
                HStack {
                    Text(NSLocalizedString("pbo.estimate.pbo", comment: "Label for PBO estimate"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pbo)
                        .font(.caption.weight(.semibold))
                }
            }

            if let gov = report.governmentEstimate {
                HStack {
                    Text(NSLocalizedString("pbo.estimate.government", comment: "Label for Government estimate"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(gov)
                        .font(.caption.weight(.semibold))
                }
            }

            if report.estimatesDisagreeSignificantly {
                Label(
                    NSLocalizedString("pbo.estimatesDiffer", comment: "Warning when estimates differ significantly"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            Link(
                NSLocalizedString("pbo.viewReport", comment: "Link to the full PBO report"),
                destination: report.reportURL
            )
            .font(.caption2)
            .accessibilityLabel(
                String(format: NSLocalizedString("pbo.viewReport.accessibility", comment: ""), report.title)
            )
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loading

    private func load() async {
        guard !bill.number.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        reports = await PBOService.fetchReports(matching: bill.number)
    }
}
