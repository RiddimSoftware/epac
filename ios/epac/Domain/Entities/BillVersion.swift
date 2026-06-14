import Foundation

/// One published version of a bill, e.g. "First reading" or "As passed by the
/// House". Sourced from LEGISinfo by the epac backend; the iOS layer never
/// scrapes LEGISinfo directly.
///
/// Civic-content rule: `label`, `chamber`, and `stage` are reproduced verbatim
/// from the backend, which in turn carries the wording Parliament publishes.
/// The diff viewer never paraphrases or summarizes these values.
struct BillVersion: Identifiable, Equatable, Sendable {
    /// Stable identifier from the backend artifact (e.g. "C-8-v1"). Used as the
    /// `from=` / `to=` argument when requesting a diff.
    let id: String

    /// Human-readable label as published by Parliament, e.g. "First reading",
    /// "Third reading", "As passed by the House".
    let label: String

    /// Optional short title carried by the backend record. Some upstream rows
    /// only carry a label, so this is a courtesy display field.
    let title: String?

    /// Legislative stage at which the version was published, verbatim from the
    /// backend (e.g. "First Reading", "Third Reading").
    let stage: String?

    /// Originating chamber for the version, verbatim from the backend
    /// (typically "House of Commons" or "Senate").
    let chamber: String?

    /// When the version was published, if known.
    let publishedOn: Date?

    /// Source link on parl.ca / LEGISinfo when the backend has one.
    let sourceURL: URL?
}
