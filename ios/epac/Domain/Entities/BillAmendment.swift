import Foundation

/// One amendment proposed to a bill during its passage through Parliament.
///
/// All values originate from the backend bill detail endpoint, which aligns
/// LEGISinfo amendment records with committee minutes from parl.ca. The
/// `text` field is the verbatim amendment language from the authoritative
/// source — this entity carries it as-is and the UI renders it without
/// transformation (verbatim authoritative text, never paraphrased).
struct BillAmendment: Identifiable, Equatable, Sendable {
    /// Stable identifier from the backend artifact.
    let id: String

    /// Caucus-prefixed amendment number, e.g. "LIB-1", "NDP-3".
    let number: String

    /// Short clause reference, e.g. "Clause 12, subsection (2)". The backend
    /// derives this from the amendment's title field.
    let clauseReference: String

    /// Disposition reported by the backend, mapped onto a known case.
    let status: BillAmendmentStatus

    /// Raw status string from the backend. Used when `status == .other` so the
    /// UI can render the source value verbatim instead of dropping it.
    let rawStatus: String

    /// Stage at which the amendment was proposed, e.g. "Committee" or "Report".
    let stage: String

    /// Name of the MP or Senator who moved the amendment. The view matches this
    /// against the local member roster to produce a profile link when possible.
    let moverName: String

    /// When the amendment was tabled, if known.
    let proposedOn: Date?

    /// Verbatim amendment text. Empty when the source has not published it yet.
    let text: String

    /// Authoritative source link (LEGISinfo or committee minutes page).
    let sourceURL: URL?
}

/// The disposition of an amendment.
///
/// Unknown values collapse to `.other` so the UI can pass them through to
/// `BillAmendment.rawStatus` rather than silently dropping unrecognized
/// dispositions.
enum BillAmendmentStatus: String, Equatable, Sendable {
    case passed
    case defeated
    case withdrawn
    case other

    /// Maps backend strings (case-insensitive) onto the typed disposition.
    /// "adopted", "agreed", "agreed to", "carried" all collapse to `.passed`;
    /// "negatived", "rejected", "lost" collapse to `.defeated`.
    init(backendValue: String) {
        let normalized = backendValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "passed", "adopted", "agreed", "agreed to", "carried":
            self = .passed
        case "defeated", "negatived", "rejected", "lost":
            self = .defeated
        case "withdrawn":
            self = .withdrawn
        default:
            self = .other
        }
    }
}
