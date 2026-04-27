//
//  PetitionDetailView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

struct PetitionDetailView: View {
    let petition: EPetition

    var body: some View {
        List {
            // MARK: - Meta section
            Section {
                LabeledContent(
                    NSLocalizedString("petitions.number", comment: ""),
                    value: petition.id
                )
                LabeledContent(
                    NSLocalizedString("petitions.status", comment: ""),
                    value: petition.status.displayName
                )
                LabeledContent(
                    NSLocalizedString("petitions.signatures", comment: ""),
                    value: "\(petition.signatureCount)"
                )
                if let deadline = petition.deadline {
                    LabeledContent(
                        NSLocalizedString("petitions.deadline", comment: ""),
                        value: deadline.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if !petition.sponsorName.isEmpty {
                    LabeledContent(
                        NSLocalizedString("petitions.sponsor", comment: ""),
                        value: petition.sponsorName
                    )
                }
            }

            // MARK: - Subject and keywords
            if !petition.subject.isEmpty || !petition.keywords.isEmpty {
                Section(NSLocalizedString("petitions.subject", comment: "")) {
                    if !petition.subject.isEmpty {
                        Text(petition.subject)
                            .font(.body)
                    }
                    if !petition.keywords.isEmpty {
                        FlowKeywordsView(keywords: petition.keywords)
                    }
                }
            }

            // MARK: - Sign link
            Section {
                Link(
                    NSLocalizedString("petitions.sign", comment: ""),
                    destination: petition.petitionURL
                )
                .foregroundStyle(Color.accentColor)
            } footer: {
                Text(NSLocalizedString("petitions.sign.footer", comment: ""))
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(petition.id)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Keyword Chips

/// Renders keyword strings as inline chips.
private struct FlowKeywordsView: View {
    let keywords: [String]

    var body: some View {
        // Use a simple wrapped layout via a LazyVStack + HStack combination.
        // A full FlowLayout requires iOS 16+ ViewThatFits juggling; for simplicity
        // we render one chip per row — clear and accessible without extra dependencies.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(keywords, id: \.self) { keyword in
                Text(keyword)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
            }
        }
    }
}
