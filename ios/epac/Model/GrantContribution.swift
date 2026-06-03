import Foundation

// Federal grant or contribution from Treasury Board Secretariat Proactive Disclosure.
// Source: open.canada.ca (Government of Canada Open Data).
// Dataset: https://open.canada.ca/data/en/dataset/432527ab-7aac-45b5-81d6-7597107a7013
// No AI-generated content.

struct GrantContribution: Identifiable, Codable {
    let id: String
    let recipientName: String
    let amount: Double
    let department: String
    let purpose: String
    let recipientLocation: String
    let recipientProvince: String
    let recipientType: String
    let fiscalYear: String
    let agreementDate: Date

    static let datasetURL = URL(string: "https://open.canada.ca/data/en/dataset/432527ab-7aac-45b5-81d6-7597107a7013")!

    var formattedAmount: String {
        GrantContribution.currencyFormatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    var recipientTypeCategory: RecipientTypeCategory {
        RecipientTypeCategory.categorize(recipientType)
    }

    enum RecipientTypeCategory: String, CaseIterable, Identifiable {
        case ngo = "NGO / Non-Profit"
        case university = "University / College"
        case municipality = "Municipality"
        case business = "Business"
        case indigenous = "Indigenous Organization"
        case individual = "Individual"
        case government = "Government"
        case other = "Other"

        var id: String { rawValue }

        static func categorize(_ raw: String) -> RecipientTypeCategory {
            let lower = raw.lowercased()
            let mapping: [(String, RecipientTypeCategory)] = [
                ("non-profit", .ngo), ("ngo", .ngo), ("non-governmental", .ngo),
                ("post-secondary", .university), ("university", .university), ("college", .university),
                ("municipal", .municipality), ("local government", .municipality),
                ("for-profit", .business), ("business", .business),
                ("indigenous", .indigenous), ("first nation", .indigenous),
                ("métis", .indigenous), ("inuit", .indigenous),
                ("individual", .individual),
                ("government", .government)
            ]
            return mapping.first(where: { lower.contains($0.0) })?.1 ?? .other
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CAD"
        f.maximumFractionDigits = 0
        return f
    }()
}
