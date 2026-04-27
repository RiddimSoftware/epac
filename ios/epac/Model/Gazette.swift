import Foundation

// Canada Gazette entry — fetched fresh from RSS, not persisted.
// Source: canadagazette.gc.ca (Government of Canada official journal).

struct GazetteEntry: Identifiable, Codable {
    let id: String
    let title: String
    let url: URL
    let publicationDate: Date
    let part: GazettePart
    let category: String
    let summary: String

    var displayCategory: String { category.isEmpty ? NSLocalizedString("gazette.category.notice", comment: "") : category }
}

enum GazettePart: String, Codable, CaseIterable, Identifiable {
    case partI  = "Part I"
    case partII = "Part II"

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .partI:  return NSLocalizedString("gazette.part.i", comment: "")
        case .partII: return NSLocalizedString("gazette.part.ii", comment: "")
        }
    }

}
