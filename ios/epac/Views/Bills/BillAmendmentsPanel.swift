import SwiftUI

private enum BillAmendmentsPanelLayout {
    static let rowSpacing = EpacSpacing.xxs
    static let headerSpacing = EpacSpacing.xs
    static let badgeHorizontalPadding: CGFloat = 6
    static let badgeVerticalPadding: CGFloat = 3
    static let moverPrefixLength = 3
}

/// The "Amendments" panel on the bill detail page.
///
/// Shows each amendment tabled against the bill with its number, mover,
/// stage, status, and short clause reference. Tapping a row reveals the
/// verbatim amendment text. Renders an explicit empty state when no
/// amendments have been tabled so users see the feature exists.
///
/// Amendment text is rendered verbatim from the backend — never paraphrased,
/// never LLM-summarized. The boundary rule lives in `LoadBillAmendments`;
/// this view consumes `BillAmendment.text` as-is.
struct BillAmendmentsPanel: View {
    let amendments: [BillAmendment]
    /// Roster of MPs used to produce a profile link when the mover name
    /// matches a known member. Empty until the parent finishes loading
    /// members from SwiftData.
    let memberRoster: [ParliamentMember]

    var body: some View {
        Section(NSLocalizedString("billAmendments.title", comment: "")) {
            if amendments.isEmpty {
                emptyStateRow
            } else {
                ForEach(amendments) { amendment in
                    BillAmendmentRow(
                        amendment: amendment,
                        moverMatch: moverMatch(for: amendment.moverName)
                    )
                    .accessibilityIdentifier("bill-amendment-row")
                }
            }
        }
    }

    private var emptyStateRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("billAmendments.empty", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("bill-amendments-empty")
    }

    private func moverMatch(for name: String) -> ParliamentMember? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.components(separatedBy: " ")
        guard let lastName = parts.last, !lastName.isEmpty else { return nil }
        let firstPrefix = String(parts.first?.prefix(BillAmendmentsPanelLayout.moverPrefixLength) ?? "")
        return memberRoster.first {
            $0.lastName.localizedCaseInsensitiveCompare(lastName) == .orderedSame &&
            (firstPrefix.isEmpty || trimmed.localizedCaseInsensitiveContains($0.firstName.prefix(BillAmendmentsPanelLayout.moverPrefixLength)))
        }
    }
}

private struct BillAmendmentRow: View {
    let amendment: BillAmendment
    let moverMatch: ParliamentMember?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.xs) {
            headerRow
            metadataRow
            if !amendment.clauseReference.isEmpty {
                Text(amendment.clauseReference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded, !amendment.text.isEmpty {
                Divider()
                Text(amendment.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("bill-amendment-text")
                if let sourceURL = amendment.sourceURL {
                    Link(NSLocalizedString("billAmendments.source", comment: ""), destination: sourceURL)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("bill-amendment-source")
                }
            } else if isExpanded {
                Text(NSLocalizedString("billAmendments.text.unavailable", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(NSLocalizedString(
            isExpanded ? "billAmendments.tap.hide" : "billAmendments.tap.reveal",
            comment: ""
        ))
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
            Text(amendment.number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: EpacSpacing.s)
            statusBadge
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
            moverView
            Spacer(minLength: EpacSpacing.s)
            if !amendment.stage.isEmpty {
                Text(amendment.stage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let proposedOn = amendment.proposedOn {
                Text(proposedOn.billAmendmentDateText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var moverView: some View {
        if amendment.moverName.isEmpty {
            EmptyView()
        } else if let member = moverMatch {
            NavigationLink(destination: MemberProfileView(member: member)) {
                Text(amendment.moverName)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bill-amendment-mover-link")
        } else {
            Text(amendment.moverName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bill-amendment-mover-text")
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, BillAmendmentsPanelLayout.badgeHorizontalPadding)
            .padding(.vertical, BillAmendmentsPanelLayout.badgeVerticalPadding)
            .background(statusColor, in: Capsule())
            .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusLabel: String {
        switch amendment.status {
        case .passed:
            return NSLocalizedString("billAmendments.status.passed", comment: "")
        case .defeated:
            return NSLocalizedString("billAmendments.status.defeated", comment: "")
        case .withdrawn:
            return NSLocalizedString("billAmendments.status.withdrawn", comment: "")
        case .other:
            return amendment.rawStatus.isEmpty
                ? NSLocalizedString("billAmendments.status.unknown", comment: "")
                : amendment.rawStatus
        }
    }

    private var statusColor: Color {
        switch amendment.status {
        case .passed:    return .appPositive
        case .defeated:  return .appDestructive
        case .withdrawn: return .appWarning
        case .other:     return .appNeutral
        }
    }

    private var statusAccessibilityLabel: String {
        String(format: NSLocalizedString("billAmendments.status.accessibility", comment: ""), statusLabel)
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
