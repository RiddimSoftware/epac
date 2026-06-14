import SwiftUI

private enum BillInCommitteePanelLayout {
    static let headerSpacing = EpacSpacing.xxs
    static let rowSpacing = EpacSpacing.xxs
    static let meetingDisplayLimit = 5
}

/// The "In committee" panel on the bill detail page.
///
/// Shows the committee studying the bill (linking to its meetings surface,
/// EPAC-411), when the study began and finished, the upcoming meetings (each
/// linking to the same committee surface), and the past meetings with their
/// witness counts. The parent only renders this panel when a committee stage
/// exists, so the panel assumes it has something to show.
struct BillInCommitteePanel: View {
    let stage: BillCommitteeStage

    private var upcomingMeetings: [BillCommitteeMeeting] {
        Array(stage.upcomingMeetings.prefix(BillInCommitteePanelLayout.meetingDisplayLimit))
    }

    private var pastMeetings: [BillCommitteeMeeting] {
        Array(stage.pastMeetings.prefix(BillInCommitteePanelLayout.meetingDisplayLimit))
    }

    var body: some View {
        Section(NSLocalizedString("billCommittee.title", comment: "")) {
            committeeRow

            if !upcomingMeetings.isEmpty {
                subheader(NSLocalizedString("billCommittee.upcoming", comment: ""))
                ForEach(upcomingMeetings) { meeting in
                    NavigationLink(destination: CommitteeMeetingsView(committee: stage.committee)) {
                        BillCommitteeMeetingRow(meeting: meeting, showsWitnessCount: false)
                    }
                    .accessibilityIdentifier("bill-in-committee-upcoming-row")
                }
            }

            if !pastMeetings.isEmpty {
                subheader(NSLocalizedString("billCommittee.past", comment: ""))
                ForEach(pastMeetings) { meeting in
                    BillCommitteeMeetingRow(meeting: meeting, showsWitnessCount: true)
                }
            }

            Link(NSLocalizedString("billCommittee.source", comment: ""), destination: stage.committee.committeeURL)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("bill-in-committee-source")
        }
    }

    private var committeeRow: some View {
        NavigationLink(destination: CommitteeMeetingsView(committee: stage.committee)) {
            VStack(alignment: .leading, spacing: BillInCommitteePanelLayout.headerSpacing) {
                Label {
                    Text(stage.committee.name)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Color.accentColor)
                }

                if let since = stage.studiedSince {
                    Text(String(
                        format: NSLocalizedString("billCommittee.studiedSince", comment: ""),
                        since.formatted(date: .abbreviated, time: .omitted)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let completed = stage.studyCompletedAt {
                    Text(String(
                        format: NSLocalizedString("billCommittee.studyCompleted", comment: ""),
                        completed.formatted(date: .abbreviated, time: .omitted)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("bill-in-committee-committee-link")
    }

    private func subheader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .listRowSeparator(.hidden)
    }
}

/// One meeting row inside the "In committee" panel. Upcoming meetings show the
/// number and date; past meetings additionally show the witness count.
private struct BillCommitteeMeetingRow: View {
    let meeting: BillCommitteeMeeting
    let showsWitnessCount: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
            VStack(alignment: .leading, spacing: BillInCommitteePanelLayout.rowSpacing) {
                Text(String(
                    format: NSLocalizedString("billCommittee.meeting.number", comment: ""),
                    meeting.meetingNumber
                ))
                .font(.subheadline.monospacedDigit())
                if let date = meeting.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: EpacSpacing.s)
            if showsWitnessCount {
                Text(witnessCountText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var witnessCountText: String {
        switch meeting.witnessCount {
        case 0:
            return NSLocalizedString("billCommittee.witness.none", comment: "")
        case 1:
            return NSLocalizedString("billCommittee.witness.singular", comment: "")
        default:
            return String(format: NSLocalizedString("billCommittee.witness.plural", comment: ""), meeting.witnessCount)
        }
    }

    private var accessibilityLabel: String {
        var parts = [String(
            format: NSLocalizedString("billCommittee.meeting.number", comment: ""),
            meeting.meetingNumber
        )]
        if let date = meeting.date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if showsWitnessCount {
            parts.append(witnessCountText)
        }
        return parts.joined(separator: ", ")
    }
}
