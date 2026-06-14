import Foundation

/// Parliamentary Budget Officer costing note linked to a bill by the epac
/// backend. All displayed civic content is backend-provided authoritative text;
/// the app does not scrape PBO pages or summarize reports on device.
struct PBOCosting: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let headlineFigureMillions: String?
    let methodologyCategory: String
    let publishedAt: Date?
    let reportURL: URL
    let sourceURL: URL?
    let summaryText: String?
}

/// Display-ready result for the bill page. The latest note is the panel's
/// primary costing; older linked notes remain available in the in-app reader.
struct PBOCostingResult: Equatable, Sendable {
    let latest: PBOCosting
    let otherReports: [PBOCosting]
}
