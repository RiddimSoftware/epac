import SwiftUI

private enum PBOCostingPanelLayout {
    static let rowSpacing = EpacSpacing.xs
    static let metadataSpacing = EpacSpacing.xs
    static let badgeHorizontalPadding: CGFloat = 7
    static let badgeVerticalPadding: CGFloat = 4
    static let titleLineLimit = 3
    static let summaryLineLimit = 8
}

/// Bill-page panel for independent PBO costing notes.
///
/// The parent passes `nil` when no backend PBO link exists; this view then
/// renders nothing, with no fallback prose.
struct PBOCostingPanel: View {
    let result: PBOCostingResult?

    @State private var isReaderPresented = false

    var body: some View {
        if let result {
            Section(NSLocalizedString("pbo.costing.sectionTitle", comment: "")) {
                Button {
                    isReaderPresented = true
                } label: {
                    PBOCostingPanelSummary(costing: result.latest, otherCount: result.otherReports.count)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pbo-costing-panel")
                .accessibilityHint(NSLocalizedString("pbo.costing.openReaderHint", comment: ""))

                Link(destination: result.latest.reportURL) {
                    Label(NSLocalizedString("pbo.costing.viewFullReport", comment: ""), systemImage: "doc.richtext")
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("pbo-costing-report-link")
            }
            .sheet(isPresented: $isReaderPresented) {
                PBOCostingReaderView(result: result)
            }
        }
    }
}

private struct PBOCostingPanelSummary: View {
    let costing: PBOCosting
    let otherCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: EpacSpacing.s) {
            VStack(alignment: .leading, spacing: PBOCostingPanelLayout.rowSpacing) {
                Text(costing.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(PBOCostingPanelLayout.titleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)

                if let headlineFigure = costing.headlineFigureMillions {
                    VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                        Text(NSLocalizedString("pbo.costing.headlineLabel", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(headlineFigure)
                            .font(.headline.monospacedDigit())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                PBOCostingMetadataRow(costing: costing)

                if otherCount > 0 {
                    Text(String(
                        format: NSLocalizedString("pbo.costing.otherReports", comment: ""),
                        otherCount
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: EpacSpacing.s)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(costing.accessibilitySummary(otherCount: otherCount))
    }
}

struct PBOCostingReaderView: View {
    let result: PBOCostingResult

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: EpacSpacing.s) {
                        Text(result.latest.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if let headlineFigure = result.latest.headlineFigureMillions {
                            VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                                Text(NSLocalizedString("pbo.costing.headlineLabel", comment: ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(headlineFigure)
                                    .font(.title3.monospacedDigit().weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }

                        PBOCostingMetadataRow(costing: result.latest)

                        if let summaryText = result.latest.summaryText {
                            Text(summaryText)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("pbo-costing-summary-text")
                        }

                        Button {
                            openURL(result.latest.reportURL)
                        } label: {
                            Label(
                                NSLocalizedString("pbo.costing.openPDFInSafari", comment: ""),
                                systemImage: "safari"
                            )
                        }
                        .accessibilityIdentifier("pbo-costing-open-pdf")
                    }
                } header: {
                    Text(NSLocalizedString("pbo.costing.readerSummary", comment: ""))
                }

                if !result.otherReports.isEmpty {
                    Section(NSLocalizedString("pbo.costing.otherReportsTitle", comment: "")) {
                        ForEach(result.otherReports) { report in
                            Link(destination: report.reportURL) {
                                VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                                    Text(report.title)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    PBOCostingMetadataRow(costing: report)
                                }
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("pbo-costing-other-report")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("pbo.costing.readerTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PBOCostingMetadataRow: View {
    let costing: PBOCosting

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: PBOCostingPanelLayout.metadataSpacing) {
                PBOCostingMethodologyBadge(category: costing.methodologyDisplayName)
                publishedDateText
            }
            VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                PBOCostingMethodologyBadge(category: costing.methodologyDisplayName)
                publishedDateText
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var publishedDateText: some View {
        if let dateText = costing.publishedDateText {
            Text(dateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PBOCostingMethodologyBadge: View {
    let category: String

    var body: some View {
        Text(category)
            .font(.caption2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.white)
            .padding(.horizontal, PBOCostingPanelLayout.badgeHorizontalPadding)
            .padding(.vertical, PBOCostingPanelLayout.badgeVerticalPadding)
            .background(Color.accentColor, in: Capsule())
    }
}

private extension PBOCosting {
    var methodologyDisplayName: String {
        switch methodologyCategory.lowercased() {
        case "legislative-cost", "legislative_cost", "legislative cost", "leg":
            return NSLocalizedString("pbo.methodology.legislativeCost", comment: "")
        case "fiscal-update", "fiscal_update", "fiscal update":
            return NSLocalizedString("pbo.methodology.fiscalUpdate", comment: "")
        case "election-platform", "election_platform", "election platform":
            return NSLocalizedString("pbo.methodology.electionPlatform", comment: "")
        case "program-evaluation", "program_evaluation", "program evaluation":
            return NSLocalizedString("pbo.methodology.programEvaluation", comment: "")
        default:
            return methodologyCategory
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    var publishedDateText: String? {
        publishedAt.map(Self.dateFormatter.string(from:))
    }

    func accessibilitySummary(otherCount: Int) -> String {
        var parts = [
            title,
            methodologyDisplayName
        ]
        if let headlineFigureMillions {
            parts.append(String(
                format: NSLocalizedString("pbo.costing.headlineAccessibility", comment: ""),
                headlineFigureMillions
            ))
        }
        if let publishedDateText {
            parts.append(publishedDateText)
        }
        if otherCount > 0 {
            parts.append(String(
                format: NSLocalizedString("pbo.costing.otherReports", comment: ""),
                otherCount
            ))
        }
        return parts.joined(separator: ", ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
