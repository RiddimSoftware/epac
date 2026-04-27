import Foundation

// Federal government contract from Treasury Board Secretariat Proactive Disclosure.
// Source: open.canada.ca (Government of Canada Open Data).
// No AI-generated content.

struct GovernmentContract: Identifiable, Codable {
    let id: String
    let department: String
    let vendor: String
    let value: Double
    let purpose: String
    let contractDate: Date
    let amendmentCount: Int
    let originalValue: Double
    let fiscalYear: String

    static let datasetURL = URL(string: "https://open.canada.ca/data/en/dataset/d8f85d91-7dec-4fd1-8055-483b77225d8b")!

    var formattedValue: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CAD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    var isHighValue: Bool { value >= 1_000_000 }
}
