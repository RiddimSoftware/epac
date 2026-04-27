//
//  PetitionsView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

struct PetitionsView: View {
    @State private var petitions: [EPetition] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var showOpenOnly = true

    private var filtered: [EPetition] {
        showOpenOnly ? petitions.filter { $0.status == .open } : petitions
    }

    var body: some View {
        Group {
            if isLoading && petitions.isEmpty {
                ProgressView()
                    .accessibilityLabel(Text("petitions.loading", comment: ""))
            } else if loadFailed && petitions.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("petitions.error.title", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(NSLocalizedString("petitions.error.description", comment: ""))
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("petitions.empty.title", comment: ""),
                    systemImage: "person.wave.2",
                    description: Text(NSLocalizedString("petitions.empty.description", comment: ""))
                )
            } else {
                List(filtered) { petition in
                    NavigationLink {
                        PetitionDetailView(petition: petition)
                    } label: {
                        PetitionRow(petition: petition)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("petitions.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showOpenOnly = false
                    } label: {
                        Label(
                            NSLocalizedString("petition.filter.all", comment: ""),
                            systemImage: showOpenOnly ? "circle" : "checkmark.circle.fill"
                        )
                    }
                    Button {
                        showOpenOnly = true
                    } label: {
                        Label(
                            NSLocalizedString("petition.status.open", comment: ""),
                            systemImage: showOpenOnly ? "checkmark.circle.fill" : "circle"
                        )
                    }
                } label: {
                    Label(
                        NSLocalizedString("petitions.filter", comment: ""),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityLabel(NSLocalizedString("petitions.filter", comment: ""))
            }
        }
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        guard petitions.isEmpty else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            petitions = try await PetitionsService.fetchOpenPetitions()
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - Row

private struct PetitionRow: View {
    let petition: EPetition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                StatusBadge(status: petition.status)
                Spacer()
                Text(
                    String(
                        format: NSLocalizedString("petitions.signatures", comment: ""),
                        petition.signatureCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(petition.id)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(petition.subject)
                .font(.subheadline)
                .lineLimit(2)

            if !petition.keywords.isEmpty {
                Text(petition.keywords.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                if !petition.sponsorName.isEmpty {
                    Text(petition.sponsorName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let deadline = petition.deadline, petition.status == .open {
                    Text(deadline, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: PetitionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(status.colorName))
            .clipShape(Capsule())
    }
}
