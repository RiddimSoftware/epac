import Foundation

/// One amendment tabled against a bill at committee, report, or third-reading
/// stage. Sourced from LEGISinfo and committee minutes via the epac backend's
/// bill-depth endpoint; the iOS layer never parses parl.ca markup directly.
///
/// Civic-content rule: `text` is the authoritative amendment text as published
/// by Parliament. The bill page renders this verbatim — no paraphrasing, no
/// summarization — per the feature's boundary rule.
struct BillAmendment: Identifiable, Equatable, Sendable {
    /// Stable identifier from the backend artifact.
    let id: String

    /// Sponsor-prefixed amendment label as published (e.g. "LIB-1", "NDP-3").
    let number: String

    /// Short title or descriptor when the backend has one. Optional because the
    /// upstream record is uneven — some amendments only carry a number.
    let title: String?

    /// The mover's display name as recorded by Parliament. The backend stores
    /// only a name string today, so this is not yet linkable to an MP profile.
    let sponsorName: String

    /// When the amendment was proposed, if known.
    let proposedOn: Date?

    /// Legislative stage the amendment was moved at, verbatim from the backend
    /// (e.g. "Committee", "Report Stage", "Third Reading").
    let stage: String

    /// Disposition reported by Parliament. `unknown` covers records the backend
    /// has not classified — render the raw `statusLabel` for those.
    let status: BillAmendmentStatus

    /// Verbatim status label as returned by the backend, used both as the
    /// fallback display when `status == .unknown` and for diagnostics.
    let statusLabel: String

    /// Authoritative amendment text, rendered verbatim on tap.
    let text: String

    /// Source link on parl.ca / LEGISinfo when the backend has one.
    let sourceURL: URL?
}

/// Disposition of a bill amendment as reported by Parliament.
///
/// The backend ingests the raw status string; this enum normalizes the
/// recurring values so the UI can colour them consistently. Anything the
/// backend has not classified maps to `unknown`, and the raw label is shown
/// instead.
enum BillAmendmentStatus: String, Equatable, Sendable {
    case passed
    case defeated
    case withdrawn
    case unknown

    /// Map a raw backend status string onto a known case. Unknown values
    /// collapse to `.unknown`, and callers should show `BillAmendment.statusLabel`
    /// verbatim in that case.
    static func from(_ rawValue: String) -> BillAmendmentStatus {
        switch rawValue.lowercased() {
        case "passed", "adopted", "agreed", "agreed_to", "agreed to", "carried":
            return .passed
        case "defeated", "rejected", "negatived":
            return .defeated
        case "withdrawn", "not_moved", "not moved":
            return .withdrawn
        default:
            return .unknown
        }
    }
}
