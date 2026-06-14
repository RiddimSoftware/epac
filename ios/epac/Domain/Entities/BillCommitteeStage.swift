import Foundation

/// A bill's committee study stage: which committee is studying the bill, when
/// the study began and finished, and the committee meetings tied to that study.
///
/// All values originate from the backend committee-stage endpoint, which aligns
/// LEGISinfo "in committee" status with the parl.ca committee schedule. The
/// boundary rule for this feature is that "hide the panel when the bill is not
/// currently before a committee" is a UI decision: the use case returns `nil`
/// when there is no active committee-stage payload, and this entity simply
/// carries whatever the backend reports. The view decides what to render.
struct BillCommitteeStage: Equatable, Sendable {
    /// The committee studying the bill. Carries enough to link to the committee
    /// meetings surface (EPAC-411) and to the committee's page.
    let committee: ParliamentaryCommittee

    /// When the committee began studying the bill, if known.
    let studiedSince: Date?

    /// When the committee finished its study, if it has. `nil` while the study
    /// is still open.
    let studyCompletedAt: Date?

    /// Scheduled meetings still to come, ordered by the backend (soonest first).
    let upcomingMeetings: [BillCommitteeMeeting]

    /// Meetings already held, ordered by the backend (most recent first), each
    /// carrying the number of witnesses the backend recorded.
    let pastMeetings: [BillCommitteeMeeting]

    /// True once the committee has finished studying the bill.
    var isStudyComplete: Bool {
        studyCompletedAt != nil
    }
}

/// One committee meeting tied to a bill's study.
struct BillCommitteeMeeting: Identifiable, Equatable, Sendable {
    let id: String

    /// Sequential meeting number within the committee's session, e.g. 45.
    let meetingNumber: Int

    /// When the meeting took place or is scheduled, if known.
    let date: Date?

    /// Number of witnesses recorded for the meeting (0 when none, or when a
    /// scheduled meeting has no witness list yet).
    let witnessCount: Int

    /// Link to the meeting's evidence/transcript on parl.ca, when published.
    let evidenceURL: URL?
}
