//
//  WitnessOrganizationView.swift
//  epac
//
//  Created on 2026-06-03.
//
//  Profile for a single organization that has testified before a parliamentary committee.
//  Sourced from committee evidence data (api.openparliament.ca).
//  All displayed data traces to authoritative Parliament of Canada sources.
//

import SwiftUI

private enum WitnessOrgLayout {
    static let rowSpacing: CGFloat = 3
    static let sectionSpacing = EpacSpacing.xs
    static let badgeSpacing: CGFloat = 6
    static let rowVerticalPadding = EpacSpacing.xxs
}

// MARK: - Outer loading wrapper

struct WitnessOrganizationView: View {
    let organizationName: String
    let committeeId: String

    @State private var org: WitnessOrganization?
    @State private var lobbyingCount: Int = 0
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && org == nil {
                ProgressView()
                    .accessibilityLabel(Text("Loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let org {
                WitnessOrganizationContent(org: org, lobbyingCount: lobbyingCount)
            } else {
                ContentUnavailableView(
                    "No appearances found",
                    systemImage: "person.fill.questionmark",
                    description: Text("No committee evidence found for this organization.")
                )
            }
        }
        .navigationTitle(organizationName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard org == nil else { return }
        isLoading = true
        defer { isLoading = false }

        let meetings = await CommitteesService.fetchRecentMeetings(committeeId: committeeId)
        org = WitnessOrganizationService.build(organizationName: organizationName, from: meetings)

        if let count = await LobbyistService.communicationCount(forOrganization: organizationName) {
            lobbyingCount = count
        }
    }
}

// MARK: - Testable content body

struct WitnessOrganizationContent: View {
    let org: WitnessOrganization
    let lobbyingCount: Int

    private static let sourceURL = URL(string: "https://www.ourcommons.ca/Committees/en/Overview")!

    var body: some View {
        List {
            if lobbyingCount > 0 {
                Section {
                    NavigationLink(destination: LobbyistOrganizationView(organizationName: org.displayName)) {
                        HStack(spacing: WitnessOrgLayout.badgeSpacing) {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text(
                                "This organization has \(lobbyingCount) registered lobbying communication\(lobbyingCount == 1 ? "" : "s") on file with the Commissioner of Lobbying."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityLabel(
                        "Lobbying cross-reference: \(lobbyingCount) communication\(lobbyingCount == 1 ? "" : "s") on file. Opens lobbyist organization profile."
                    )
                }
            }

            Section("Appearances (\(org.totalAppearances))") {
                ForEach(org.appearances) { appearance in
                    AppearanceRow(appearance: appearance)
                }
            }

            if !org.subjects.isEmpty {
                Section("Subjects") {
                    ForEach(org.subjects, id: \.self) { subject in
                        Text(subject)
                            .font(.subheadline)
                            .padding(.vertical, WitnessOrgLayout.rowVerticalPadding)
                    }
                }
            }

            if !org.individualWitnesses.isEmpty {
                Section("Witnesses") {
                    ForEach(org.individualWitnesses) { witness in
                        WitnessDetailRow(witness: witness)
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                Link("Source: parl.ca committee evidence", destination: Self.sourceURL)
                    .font(.caption2)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Appearance row

private struct AppearanceRow: View {
    let appearance: CommitteeAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: WitnessOrgLayout.rowSpacing) {
            HStack {
                Text(appearance.committeeName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                if let date = appearance.hearingDate {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let first = appearance.subjects.first {
                Text(first)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let url = appearance.publicationURL {
                Link("View transcript", destination: url)
                    .font(.caption2)
            }
        }
        .padding(.vertical, WitnessOrgLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Witness detail row

struct WitnessDetailRow: View {
    let witness: CommitteeWitness

    var body: some View {
        VStack(alignment: .leading, spacing: WitnessOrgLayout.rowSpacing) {
            Text(witness.name)
                .font(.subheadline.weight(.semibold))
            if !witness.title.isEmpty {
                Text(witness.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, WitnessOrgLayout.rowVerticalPadding)
    }
}
