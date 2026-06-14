import Foundation

/// A structured clause-level diff between two published bill versions.
///
/// The diff respects the clause/sub-clause structure published by Parliament —
/// it is not a raw line-by-line text diff. The backend computes the diff and
/// emits one `BillClauseDiff` per clause that differs between the two
/// versions, with optional `unchanged` clauses for context when the backend
/// includes them.
///
/// Civic-content rule: every `fromText`/`toText` value is the authoritative
/// clause text. The view renders text verbatim — no LLM summaries.
struct BillVersionDiff: Equatable, Sendable {
    /// Version the diff is computed against (the "before" side).
    let fromVersion: BillVersion

    /// Version the diff is computed against (the "after" side).
    let toVersion: BillVersion

    /// Clause-level diffs in the order Parliament publishes the clauses, from
    /// the start of the bill onwards.
    let clauseDiffs: [BillClauseDiff]
}

/// One clause within a bill diff, carrying the change kind, the verbatim
/// before/after clause text, and an optional anchor back to the chamber speech
/// that introduced the change (when the backend knows it).
struct BillClauseDiff: Identifiable, Equatable, Sendable {
    /// Stable identifier from the backend (typically the clause anchor, e.g.
    /// "clause-3-1"). Falls back to a synthesised string if the backend omits.
    let id: String

    /// Human-readable label as published by Parliament (e.g. "Clause 3",
    /// "Subclause 5(2)").
    let label: String

    /// Change kind for the clause.
    let changeType: BillClauseChangeType

    /// Verbatim clause text from the "before" version. Empty for purely
    /// added clauses.
    let fromText: String

    /// Verbatim clause text from the "after" version. Empty for purely
    /// removed clauses.
    let toText: String

    /// Anchor URL into Hansard for the chamber speech that introduced the
    /// change, when the backend has one. The bill page links the clause row
    /// out to this URL.
    let hansardAnchorURL: URL?
}

/// Kind of change a `BillClauseDiff` represents.
///
/// `unchanged` is included for backend records that emit context clauses —
/// the view collapses unchanged clauses by default.
enum BillClauseChangeType: String, Equatable, Sendable {
    case added
    case removed
    case modified
    case unchanged

    /// Map a raw backend change-type string onto a known case. Unknown values
    /// collapse to `.modified` (the safer "treat as a change" default).
    static func from(_ rawValue: String) -> BillClauseChangeType {
        switch rawValue.lowercased() {
        case "added", "insert", "inserted", "new":
            return .added
        case "removed", "deleted", "delete":
            return .removed
        case "unchanged", "same", "context":
            return .unchanged
        case "modified", "changed", "replace", "replaced":
            return .modified
        default:
            return .modified
        }
    }
}
