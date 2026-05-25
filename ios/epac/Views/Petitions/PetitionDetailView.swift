//
//  PetitionDetailView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

private enum PetitionDetailLayout {
    static let signatureSpacing = EpacSpacing.xs
    static let signatureFontSize: CGFloat = 44
    static let signatureThreshold = 500
    static let progressTopPadding = EpacSpacing.xs
    static let signatureVerticalPadding = EpacSpacing.s
    static let keywordSpacing = EpacSpacing.xs
    static let keywordHorizontalPadding = EpacSpacing.s
    static let keywordVerticalPadding: CGFloat = 3
}

struct PetitionDetailView: View {
    let petition: EPetition

    var body: some View {
        List {
            // MARK: - Signature count hero
            Section {
                VStack(spacing: PetitionDetailLayout.signatureSpacing) {
                    Text("\(petition.signatureCount)")
                        .font(.system(size: PetitionDetailLayout.signatureFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(petition.status == .open ? Color.accentColor : Color.secondary)
                    Text(NSLocalizedString("petitions.signatures.label", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if petition.status == .open && petition.signatureCount < PetitionDetailLayout.signatureThreshold {
                        ProgressView(value: Double(petition.signatureCount), total: Double(PetitionDetailLayout.signatureThreshold))
                            .tint(.accentColor)
                            .padding(.top, PetitionDetailLayout.progressTopPadding)
                        Text(String(format: NSLocalizedString("petitions.signatures.threshold", comment: ""), PetitionDetailLayout.signatureThreshold - petition.signatureCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PetitionDetailLayout.signatureVerticalPadding)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(petition.signatureCount) \(NSLocalizedString("petitions.signatures.label", comment: ""))")
            }

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
        VStack(alignment: .leading, spacing: PetitionDetailLayout.keywordSpacing) {
            ForEach(keywords, id: \.self) { keyword in
                Text(keyword)
                    .font(.caption)
                    .padding(.horizontal, PetitionDetailLayout.keywordHorizontalPadding)
                    .padding(.vertical, PetitionDetailLayout.keywordVerticalPadding)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
            }
        }
    }
}
