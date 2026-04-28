//
//  ParliamentaryTopic.swift
//  epac
//
//  A curated, static controlled vocabulary of Parliamentary topics.
//  Keywords are drawn from Parliament's own classification of Hansard
//  SubjectOfBusiness titles and LEGISinfo bill titles — not inferred.
//

import Foundation

struct ParliamentaryTopic: Identifiable, Codable, Hashable {
    let id: String          // stable lowercase slug, e.g. "housing"
    let nameKey: String     // localization key, e.g. "topic.housing"
    let keywords: [String]  // case-insensitive substrings to match in titles

    var localizedName: String { NSLocalizedString(nameKey, comment: "") }

    static let all: [ParliamentaryTopic] = [
        ParliamentaryTopic(id: "housing", nameKey: "topic.housing", keywords: ["housing", "rent", "mortgage", "affordable housing", "logement", "loyer"]),
        ParliamentaryTopic(id: "healthcare", nameKey: "topic.healthcare", keywords: ["health", "pharmacare", "mental health", "dental", "pandemic", "santé"]),
        ParliamentaryTopic(id: "climate", nameKey: "topic.climate", keywords: ["climate", "carbon", "environment", "clean energy", "net zero", "emission", "énergie", "environnement"]),
        ParliamentaryTopic(id: "economy", nameKey: "topic.economy", keywords: ["budget", "fiscal", "inflation", "economic", "gdp", "debt", "déficit", "économie"]),
        ParliamentaryTopic(id: "indigenous", nameKey: "topic.indigenous", keywords: ["indigenous", "first nations", "métis", "inuit", "reconciliation", "autochtone"]),
        ParliamentaryTopic(id: "immigration", nameKey: "topic.immigration", keywords: ["immigration", "refugee", "asylum", "citizenship", "border", "réfugié"]),
        ParliamentaryTopic(id: "defence", nameKey: "topic.defence", keywords: ["defence", "military", "NATO", "armed forces", "défense", "armée"]),
        ParliamentaryTopic(id: "justice", nameKey: "topic.justice", keywords: ["justice", "crime", "police", "firearms", "gun", "corrections", "sécurité"]),
        ParliamentaryTopic(id: "seniors", nameKey: "topic.seniors", keywords: ["senior", "pension", "retirement", "old age", "aîné", "retraite"]),
        ParliamentaryTopic(id: "agriculture", nameKey: "topic.agriculture", keywords: ["agriculture", "farming", "food security", "grain", "livestock"]),
        ParliamentaryTopic(id: "transport", nameKey: "topic.transport", keywords: ["transport", "rail", "aviation", "highway", "infrastructure", "transit"]),
        ParliamentaryTopic(id: "taxation", nameKey: "topic.taxation", keywords: ["tax", "GST", "HST", "income tax", "corporate tax", "impôt", "taxe"]),
        ParliamentaryTopic(id: "foreign", nameKey: "topic.foreign", keywords: ["foreign affairs", "international", "Ukraine", "Gaza", "sanctions", "treaty", "affaires étrangères"]),
        ParliamentaryTopic(id: "education", nameKey: "topic.education", keywords: ["education", "student", "university", "school", "tuition", "éducation", "étudiant"]),
        ParliamentaryTopic(id: "childcare", nameKey: "topic.childcare", keywords: ["child care", "daycare", "family", "children", "services de garde", "enfant"]),
        ParliamentaryTopic(id: "energy", nameKey: "topic.energy", keywords: ["energy", "oil", "gas", "pipeline", "electricity", "LNG", "pétrole"]),
        ParliamentaryTopic(id: "pharma", nameKey: "topic.pharma", keywords: ["drug", "pharmaceutical", "medication", "opioid", "naloxone", "médicament"]),
        ParliamentaryTopic(id: "digital", nameKey: "topic.digital", keywords: ["digital", "artificial intelligence", "AI", "online harms", "privacy", "cybersecurity", "numérique"]),
        ParliamentaryTopic(id: "labour", nameKey: "topic.labour", keywords: ["labour", "labor", "union", "strike", "wage", "employment", "travail", "grève"]),
        ParliamentaryTopic(id: "trade", nameKey: "topic.trade", keywords: ["trade", "tariff", "CUSMA", "CETA", "export", "import", "commerce", "tarif"])
    ]

    /// Returns all topics whose keywords match the given text.
    static func matching(_ text: String) -> [ParliamentaryTopic] {
        let lower = text.lowercased()
        return all.filter { topic in
            topic.keywords.contains { lower.contains($0.lowercased()) }
        }
    }
}
