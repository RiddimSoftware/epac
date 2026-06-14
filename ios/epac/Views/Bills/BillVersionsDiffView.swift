import SwiftUI

private enum BillVersionsDiffLayout {
    static let rowSpacing = EpacSpacing.xs
    static let badgePaddingH: CGFloat = 6
    static let badgePaddingV: CGFloat = 3
    static let textPaddingTop: CGFloat = 4
    static let columnSpacing: CGFloat = 12
    static let dividerWidth: CGFloat = 1
    static let pillCorner: CGFloat = 4
    static let highlightOpacity: Double = 0.18

    /// A diff requires at least one "before" and one "after" version. Below
    /// this threshold the diff viewer renders an empty state and the
    /// view-mode picker is hidden.
    static let minimumVersionsForDiff = 2
}

/// Display mode for the diff list — toggleable from the toolbar.
enum BillVersionsDiffViewMode: String, CaseIterable, Identifiable, Sendable {
    case inline
    case sideBySide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inline:
            return NSLocalizedString("billDiff.mode.inline", comment: "")
        case .sideBySide:
            return NSLocalizedString("billDiff.mode.sideBySide", comment: "")
        }
    }
}

/// "Compare versions" sheet for a bill.
///
/// Renders one row per clause-level diff between the two selected versions,
/// with additions / deletions / modifications highlighted, an inline ↔ side-
/// by-side toggle, and a tap-through to the Hansard speech that introduced
/// each change when the backend has the anchor. Verbatim text only — there is
/// no LLM summary anywhere on the surface.
///
/// Three structural states drive the UI:
///   - `nil` versions: backend has no version record at all — the bill page
///     hides the entry point before this view is ever instantiated.
///   - `versions.count <= 1`: empty-state row explaining only one version
///     has been published.
///   - `versions.count >= 2`: pickers to choose `from`/`to`, then the diff.
struct BillVersionsDiffView: View {
    let billNumber: String
    let versions: [BillVersion]
    let loadBillVersionDiff: LoadBillVersionDiff
    let billID: String

    @State private var fromVersionID: String
    @State private var toVersionID: String
    @State private var viewMode: BillVersionsDiffViewMode = .inline
    @State private var diff: BillVersionDiff?
    @State private var isLoading = false
    @State private var loadFailed = false

    @Environment(\.dismiss) private var dismiss

    init(
        billNumber: String,
        billID: String,
        versions: [BillVersion],
        loadBillVersionDiff: LoadBillVersionDiff = LoadBillVersionDiff(
            repository: BackendBillVersionDiffRepository()
        )
    ) {
        self.billNumber = billNumber
        self.billID = billID
        self.versions = versions
        self.loadBillVersionDiff = loadBillVersionDiff

        let sorted = Self.sortVersions(versions)
        self._fromVersionID = State(initialValue: sorted.first?.id ?? "")
        self._toVersionID = State(initialValue: sorted.last?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(billNumber)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(NSLocalizedString("billDiff.close", comment: "")) {
                            dismiss()
                        }
                    }
                    if versions.count >= BillVersionsDiffLayout.minimumVersionsForDiff {
                        ToolbarItem(placement: .topBarTrailing) {
                            Picker(NSLocalizedString("billDiff.mode.picker", comment: ""), selection: $viewMode) {
                                ForEach(BillVersionsDiffViewMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("bill-diff-mode-picker")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if versions.count < BillVersionsDiffLayout.minimumVersionsForDiff {
            emptyState
        } else {
            List {
                versionPickersSection
                diffSection
                sourceSection
            }
            .listStyle(.insetGrouped)
            .task(id: diffTaskKey) { await loadDiff() }
        }
    }

    private var diffTaskKey: String {
        "\(fromVersionID)::\(toVersionID)"
    }

    private var versionPickersSection: some View {
        Section(NSLocalizedString("billDiff.compare.title", comment: "")) {
            Picker(NSLocalizedString("billDiff.from", comment: ""), selection: $fromVersionID) {
                ForEach(versions) { version in
                    Text(displayLabel(for: version)).tag(version.id)
                }
            }
            .accessibilityIdentifier("bill-diff-from-picker")

            Picker(NSLocalizedString("billDiff.to", comment: ""), selection: $toVersionID) {
                ForEach(versions) { version in
                    Text(displayLabel(for: version)).tag(version.id)
                }
            }
            .accessibilityIdentifier("bill-diff-to-picker")
        }
    }

    @ViewBuilder
    private var diffSection: some View {
        if isLoading {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                        .accessibilityIdentifier("bill-diff-loading")
                    Spacer()
                }
            }
        } else if loadFailed {
            Section {
                Text(NSLocalizedString("billDiff.error", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bill-diff-error")
            }
        } else if let diff {
            if diff.clauseDiffs.isEmpty {
                Section {
                    Text(NSLocalizedString("billDiff.noChanges", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("bill-diff-no-changes")
                }
            } else {
                Section(NSLocalizedString("billDiff.changes.title", comment: "")) {
                    ForEach(diff.clauseDiffs) { clause in
                        BillClauseDiffRow(
                            clause: clause,
                            viewMode: viewMode
                        )
                        .accessibilityIdentifier("bill-diff-row")
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        Section {
            Text(NSLocalizedString("billDiff.source", comment: ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("bill-diff-source")
        }
    }

    private var emptyState: some View {
        VStack(spacing: EpacSpacing.m) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(NSLocalizedString("billDiff.empty.title", comment: ""))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("billDiff.empty.body", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, EpacSpacing.l)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("bill-diff-empty")
    }

    private func displayLabel(for version: BillVersion) -> String {
        var parts: [String] = []
        if !version.label.isEmpty {
            parts.append(version.label)
        }
        if let published = version.publishedOn {
            parts.append(published.billVersionDateText)
        }
        if parts.isEmpty {
            return version.id
        }
        return parts.joined(separator: " — ")
    }

    @MainActor
    private func loadDiff() async {
        guard !fromVersionID.isEmpty, !toVersionID.isEmpty else {
            diff = nil
            return
        }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            diff = try await loadBillVersionDiff.execute(
                billID: billID,
                fromVersionID: fromVersionID,
                toVersionID: toVersionID
            )
            loadFailed = diff == nil
        } catch {
            diff = nil
            loadFailed = true
        }
    }

    private static func sortVersions(_ versions: [BillVersion]) -> [BillVersion] {
        versions.sorted { lhs, rhs in
            switch (lhs.publishedOn, rhs.publishedOn) {
            case let (l?, r?):
                return l < r
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (nil, nil):
                return lhs.label < rhs.label
            }
        }
    }
}

/// Pure-rendering surface for an already-loaded diff. Lets snapshot tests
/// exercise the diff list without going through the async loader on
/// `BillVersionsDiffView`.
struct BillVersionsDiffContent: View {
    let diff: BillVersionDiff
    let viewMode: BillVersionsDiffViewMode

    var body: some View {
        List {
            if diff.clauseDiffs.isEmpty {
                Section {
                    Text(NSLocalizedString("billDiff.noChanges", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("bill-diff-no-changes")
                }
            } else {
                Section(NSLocalizedString("billDiff.changes.title", comment: "")) {
                    ForEach(diff.clauseDiffs) { clause in
                        BillClauseDiffRow(
                            clause: clause,
                            viewMode: viewMode
                        )
                        .accessibilityIdentifier("bill-diff-row")
                    }
                }
            }

            Section {
                Text(NSLocalizedString("billDiff.source", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("bill-diff-source")
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// One row inside the diff list. Shows the clause label, a change-type badge,
/// and either an inline before/after stack or a two-column side-by-side
/// presentation. Tapping the Hansard anchor link opens the chamber speech
/// that introduced the change when the backend records it.
struct BillClauseDiffRow: View {
    let clause: BillClauseDiff
    let viewMode: BillVersionsDiffViewMode

    var body: some View {
        VStack(alignment: .leading, spacing: BillVersionsDiffLayout.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
                Text(clauseLabel)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: EpacSpacing.s)
                BillClauseChangeBadge(
                    changeType: clause.changeType,
                    label: changeTypeLabel
                )
            }

            switch viewMode {
            case .inline:
                inlineBody
            case .sideBySide:
                sideBySideBody
            }

            if let hansardURL = clause.hansardAnchorURL {
                Link(
                    NSLocalizedString("billDiff.openHansard", comment: ""),
                    destination: hansardURL
                )
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("bill-diff-hansard-link")
            }
        }
        .padding(.vertical, BillVersionsDiffLayout.textPaddingTop)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var inlineBody: some View {
        switch clause.changeType {
        case .added:
            highlightedText(clause.toText, kind: .added)
        case .removed:
            highlightedText(clause.fromText, kind: .removed)
        case .modified:
            VStack(alignment: .leading, spacing: BillVersionsDiffLayout.rowSpacing) {
                highlightedText(clause.fromText, kind: .removed)
                highlightedText(clause.toText, kind: .added)
            }
        case .unchanged:
            Text(clause.toText.isEmpty ? clause.fromText : clause.toText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var sideBySideBody: some View {
        HStack(alignment: .top, spacing: BillVersionsDiffLayout.columnSpacing) {
            sideColumn(
                title: NSLocalizedString("billDiff.column.before", comment: ""),
                text: clause.fromText,
                kind: .removed,
                isEmpty: clause.changeType == .added
            )
            Rectangle()
                .fill(Color.appDivider)
                .frame(width: BillVersionsDiffLayout.dividerWidth)
            sideColumn(
                title: NSLocalizedString("billDiff.column.after", comment: ""),
                text: clause.toText,
                kind: .added,
                isEmpty: clause.changeType == .removed
            )
        }
    }

    private func sideColumn(
        title: String,
        text: String,
        kind: BillClauseHighlightKind,
        isEmpty: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if isEmpty || text.isEmpty {
                Text(NSLocalizedString("billDiff.column.absent", comment: ""))
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
            } else if clause.changeType == .unchanged {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                highlightedText(text, kind: kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightedText(_ text: String, kind: BillClauseHighlightKind) -> some View {
        Text(text)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(EpacSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BillVersionsDiffLayout.pillCorner)
                    .fill(kind.color.opacity(BillVersionsDiffLayout.highlightOpacity))
            )
            .accessibilityIdentifier("bill-diff-text-\(kind.identifierSuffix)")
    }

    private var clauseLabel: String {
        clause.label.isEmpty
            ? NSLocalizedString("billDiff.clausePlaceholder", comment: "")
            : clause.label
    }

    private var changeTypeLabel: String {
        switch clause.changeType {
        case .added:
            return NSLocalizedString("billDiff.changeType.added", comment: "")
        case .removed:
            return NSLocalizedString("billDiff.changeType.removed", comment: "")
        case .modified:
            return NSLocalizedString("billDiff.changeType.modified", comment: "")
        case .unchanged:
            return NSLocalizedString("billDiff.changeType.unchanged", comment: "")
        }
    }

    private var accessibilityLabel: String {
        [clauseLabel, changeTypeLabel]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private enum BillClauseHighlightKind {
    case added
    case removed

    var color: Color {
        switch self {
        case .added: return .appPositive
        case .removed: return .appDestructive
        }
    }

    var identifierSuffix: String {
        switch self {
        case .added: return "added"
        case .removed: return "removed"
        }
    }
}

private struct BillClauseChangeBadge: View {
    let changeType: BillClauseChangeType
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.white)
            .padding(.horizontal, BillVersionsDiffLayout.badgePaddingH)
            .padding(.vertical, BillVersionsDiffLayout.badgePaddingV)
            .background(colorFor(changeType), in: Capsule())
            .accessibilityHidden(true)
    }

    private func colorFor(_ changeType: BillClauseChangeType) -> Color {
        switch changeType {
        case .added: return .appPositive
        case .removed: return .appDestructive
        case .modified: return .appWarning
        case .unchanged: return .appNeutral
        }
    }
}

private extension Date {
    var billVersionDateText: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
