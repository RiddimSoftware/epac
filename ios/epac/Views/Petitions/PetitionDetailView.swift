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
    private let queryPort: any PetitionGovernmentResponseQueryPort

    @State private var response: PetitionGovernmentResponse?
    @State private var isLoading = false
    @State private var loadFailed = false

    init(
        petition: EPetition,
        queryPort: any PetitionGovernmentResponseQueryPort = BackendPetitionGovernmentResponseQueryPort()
    ) {
        self.petition = petition
        self.queryPort = queryPort
    }

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

            // MARK: - Government Response Section
            responseSection

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
        .adaptiveReadingWidth()
        .navigationTitle(petition.id)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadResponse()
        }
    }

    // MARK: - Government Response UI

    @ViewBuilder
    private var responseSection: some View {
        if isLoading {
            Section(NSLocalizedString("petitions.response.section", comment: "")) {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        } else if let response = response {
            Section(NSLocalizedString("petitions.response.section", comment: "")) {
                VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                    if let minister = response.respondingMinister, !minister.isEmpty {
                        Text(NSLocalizedString("petitions.response.minister", comment: ""))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(minister)
                            .font(.subheadline)
                    }

                    Text(String(format: NSLocalizedString("petitions.response.tabled", comment: ""), response.tabledOn.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, EpacSpacing.xxs)

                    Text(response.text)
                        .font(.body)
                }
            }
        } else if loadFailed {
            Section(NSLocalizedString("petitions.response.section", comment: "")) {
                HStack {
                    Text(NSLocalizedString("petitions.error.description", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(NSLocalizedString("Retry", comment: "")) {
                        Task {
                            await loadResponse()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        } else {
            // Check if it qualified
            if petition.signatureCount >= 500 {
                Section(NSLocalizedString("petitions.response.section", comment: "")) {
                    HStack(spacing: EpacSpacing.xs) {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.orange)
                        Text(NSLocalizedString("petitions.response.awaiting", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if petition.status == .closed || petition.status == .certified || petition.status == .responseReceived {
                // Closed or certified and did not reach 500 signatures: did not qualify
                Section(NSLocalizedString("petitions.response.section", comment: "")) {
                    HStack(spacing: EpacSpacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("petitions.response.notQualified", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func loadResponse() async {
        if let existing = petition.governmentResponse {
            self.response = existing
            return
        }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let useCase = LoadPetitionGovernmentResponse(queryPort: queryPort)
            self.response = try await useCase.execute(petitionID: petition.id)
        } catch {
            loadFailed = true
        }
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
