// ExplainerCard.swift
// epac
//
// Contextual "What is this?" sheet for parliamentary terms.
// Data is sourced from explainers.json in the app bundle and cites
// Parliament of Canada authoritative sources.

import SwiftUI

// MARK: - Model

struct Explainer: Decodable {
    let term: String
    let definition: String
    let sourceLabel: String
    let learnMoreURL: URL
}

// MARK: - Repository

final class ExplainerRepository: @unchecked Sendable {
    static let shared = ExplainerRepository()

    private let index: [String: Explainer]

    private init() {
        guard let url = Bundle.main.url(forResource: "explainers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Explainer].self, from: data) else {
            index = [:]
            return
        }
        // Index by lowercased term for case-insensitive lookup
        index = Dictionary(uniqueKeysWithValues: list.map { ($0.term.lowercased(), $0) })
    }

    /// Internal initializer for unit tests — accepts a JSON string directly
    /// so tests don't depend on the main bundle.
    init(json: String) {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Explainer].self, from: data) else {
            index = [:]
            return
        }
        index = Dictionary(uniqueKeysWithValues: list.map { ($0.term.lowercased(), $0) })
    }

    func explainer(for term: String) -> Explainer? {
        index[term.lowercased()]
    }
}

// MARK: - Card view

struct ExplainerCard: View {
    let explainer: Explainer

    private enum Layout {
        static let sectionSpacing: CGFloat = 20
        static let sheetDetentFraction = 0.45
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            VStack(alignment: .leading, spacing: EpacSpacing.s) {
                Text(explainer.term)
                    .font(.title2.bold())
                Text(explainer.definition)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Divider()

            HStack(alignment: .top, spacing: EpacSpacing.s) {
                Image(systemName: "building.columns")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                    Text(explainer.sourceLabel)
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                    Link("Learn more →", destination: explainer.learnMoreURL)
                        .font(.footnote)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(EpacSpacing.l)
        .presentationDetents([.fraction(Layout.sheetDetentFraction)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Tip modifier

/// Wraps a `Text` label in an HStack with a `?` button that presents the
/// matching explainer card for that term. No-ops silently when the term is
/// not in the explainer index, so call sites need no guarding.
struct ExplainerTipModifier: ViewModifier {
    let term: String

    @State private var showExplainer = false

    private var explainer: Explainer? {
        ExplainerRepository.shared.explainer(for: term)
    }

    func body(content: Content) -> some View {
        if let explainer {
            HStack(spacing: EpacSpacing.xs) {
                content
                Button {
                    showExplainer = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What is \(term)?")
            }
            .regularSizeClassFormSheet(isPresented: $showExplainer) {
                ExplainerCard(explainer: explainer)
            }
        } else {
            content
        }
    }
}

extension View {
    func explainerTip(for term: String) -> some View {
        modifier(ExplainerTipModifier(term: term))
    }
}
