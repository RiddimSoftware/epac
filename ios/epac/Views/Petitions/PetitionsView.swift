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
    @State private var searchText = ""

    private var filtered: [EPetition] {
        let statusFiltered = showOpenOnly ? petitions.filter { $0.status == .open } : petitions
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return statusFiltered }
        return statusFiltered.filter {
            $0.subject.localizedCaseInsensitiveContains(q) ||
            $0.id.localizedCaseInsensitiveContains(q) ||
            $0.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        Group {
            if isLoading && petitions.isEmpty {
                ProgressView()
                    .accessibilityLabel(Text("petitions.loading", comment: ""))
            } else if loadFailed && petitions.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: NSLocalizedString("petitions.error.title", comment: ""),
                    message: NSLocalizedString("petitions.error.description", comment: ""),
                    action: EmptyStateAction(label: NSLocalizedString("Retry", comment: ""), handler: { Task { await load() } })
                )
            } else if filtered.isEmpty && showOpenOnly {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: NSLocalizedString("petitions.noOpen.title", comment: ""),
                    message: NSLocalizedString("petitions.noOpen.description", comment: ""),
                    action: EmptyStateAction(label: NSLocalizedString("petition.filter.all", comment: ""), handler: {
                        showOpenOnly = false
                    })
                )
            } else if filtered.isEmpty {
                EmptyStateView(
                    icon: "person.wave.2",
                    title: NSLocalizedString("petitions.empty.title", comment: ""),
                    message: NSLocalizedString("petitions.empty.description", comment: ""),
                    action: nil
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
                .refreshable {
                    petitions = []
                    await load()
                }
            }
        }
        .navigationTitle(NSLocalizedString("petitions.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: NSLocalizedString("petitions.search.prompt", comment: "")
        )
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
        .accessibilityLabel("\(petition.status.displayName): \(petition.subject)")
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
            .background(status.color)
            .clipShape(Capsule())
    }
}
