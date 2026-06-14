import SwiftUI

private enum BillAmendmentsPanelLayout {
    static let rowSpacing = EpacSpacing.xxs
    static let badgePaddingH: CGFloat = 6
    static let badgePaddingV: CGFloat = 3
    static let textPaddingTop: CGFloat = 4
    static let amendmentDisplayLimit = 50
}

/// The "Amendments" panel on the bill detail page.
///
/// Renders one row per tabled amendment, with the amendment number, the
/// mover's name as recorded by Parliament, the stage at which it was moved,
/// and a coloured status badge (passed / defeated / withdrawn). Tapping a row
/// reveals the full authoritative amendment text verbatim — the panel does no
/// paraphrasing or summarization.
///
/// The parent shows an empty-state row in the same section when the backend
/// returns an empty array (bill tracked, no amendments tabled yet); the
/// parent hides the entire panel when the backend has no amendments record
/// for the bill at all.
struct BillAmendmentsPanel: View {
    let amendments: [BillAmendment]

    private var displayedAmendments: [BillAmendment] {
        Array(amendments.prefix(BillAmendmentsPanelLayout.amendmentDisplayLimit))
    }

    var body: some View {
        Section(NSLocalizedString("billAmendments.title", comment: "")) {
            if amendments.isEmpty {
                emptyRow
            } else {
                ForEach(displayedAmendments) { amendment in
                    BillAmendmentRow(amendment: amendment)
                        .accessibilityIdentifier("bill-amendments-row")
                }
            }

            Text(NSLocalizedString("billAmendments.source", comment: ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("bill-amendments-source")
        }
    }

    private var emptyRow: some View {
        Label {
            Text(NSLocalizedString("billAmendments.empty", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("bill-amendments-empty")
    }
}

/// One row inside the "Amendments" panel. Collapsed shows number, mover,
/// stage, and a status badge; tap expands to reveal the verbatim text and
/// source link when available.
private struct BillAmendmentRow: View {
    let amendment: BillAmendment

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            expandedContent
        } label: {
            collapsedLabel
        }
        .accessibilityAction(named: isExpanded
            ? NSLocalizedString("billAmendments.collapse", comment: "")
            : NSLocalizedString("billAmendments.expand", comment: "")
        ) {
            isExpanded.toggle()
        }
    }

    private var collapsedLabel: some View {
        VStack(alignment: .leading, spacing: BillAmendmentsPanelLayout.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
                Text(amendment.number.isEmpty
                    ? NSLocalizedString("billAmendments.numberPlaceholder", comment: "")
                    : amendment.number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: EpacSpacing.s)
                BillAmendmentStatusBadge(status: amendment.status, label: statusDisplayLabel)
            }

            if !amendment.sponsorName.isEmpty {
                Text(String(
                    format: NSLocalizedString("billAmendments.movedBy", comment: ""),
                    amendment.sponsorName
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let title = amendment.title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: EpacSpacing.s) {
                if !amendment.stage.isEmpty {
                    Text(amendment.stage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let proposedOn = amendment.proposedOn {
                    Text(proposedOn.billAmendmentDateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if amendment.text.isEmpty {
            Text(NSLocalizedString("billAmendments.textUnavailable", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, BillAmendmentsPanelLayout.textPaddingTop)
        } else {
            Text(amendment.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, BillAmendmentsPanelLayout.textPaddingTop)
                .accessibilityIdentifier("bill-amendments-text")
        }

        if let sourceURL = amendment.sourceURL {
            Link(NSLocalizedString("billAmendments.openSource", comment: ""), destination: sourceURL)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("bill-amendments-source-link")
        }
    }

    private var statusDisplayLabel: String {
        switch amendment.status {
        case .passed:
            return NSLocalizedString("billAmendments.status.passed", comment: "")
        case .defeated:
            return NSLocalizedString("billAmendments.status.defeated", comment: "")
        case .withdrawn:
            return NSLocalizedString("billAmendments.status.withdrawn", comment: "")
        case .unknown:
            return amendment.statusLabel.isEmpty
                ? NSLocalizedString("billAmendments.status.unknown", comment: "")
                : amendment.statusLabel
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if !amendment.number.isEmpty {
            parts.append(amendment.number)
        }
        if !amendment.sponsorName.isEmpty {
            parts.append(String(
                format: NSLocalizedString("billAmendments.movedBy", comment: ""),
                amendment.sponsorName
            ))
        }
        if !amendment.stage.isEmpty {
            parts.append(amendment.stage)
        }
        parts.append(statusDisplayLabel)
        if let proposedOn = amendment.proposedOn {
            parts.append(proposedOn.billAmendmentDateText)
        }
        return parts.joined(separator: ", ")
    }
}

/// Coloured pill matching the conventions used elsewhere on the bill page
/// (e.g. `BillHeaderBadge`): semantic colour by status, white text, capsule.
private struct BillAmendmentStatusBadge: View {
    let status: BillAmendmentStatus
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.white)
            .padding(.horizontal, BillAmendmentsPanelLayout.badgePaddingH)
            .padding(.vertical, BillAmendmentsPanelLayout.badgePaddingV)
            .background(colorFor(status), in: Capsule())
            .accessibilityHidden(true)
    }

    private func colorFor(_ status: BillAmendmentStatus) -> Color {
        switch status {
        case .passed:
            return .appPositive
        case .defeated:
            return .appDestructive
        case .withdrawn:
            return .appWarning
        case .unknown:
            return .appNeutral
        }
    }
}

private extension Date {
    var billAmendmentDateText: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
