//
//  LobbyingView.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Full-screen list of lobbying communications registered against an MP
//  in the Commissioner of Lobbying open dataset. Linked from MemberProfileView.
//

import SwiftUI

struct LobbyingView: View {
    let member: ParliamentMember

    @State private var communications: [LobbyistCommunication] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading && communications.isEmpty {
                ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed && communications.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("lobbying.error.title", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(NSLocalizedString("lobbying.error.description", comment: ""))
                )
            } else if communications.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("lobbying.empty.title", comment: ""),
                    systemImage: "person.fill.badge.plus",
                    description: Text(NSLocalizedString("lobbying.empty.description", comment: ""))
                )
            } else {
                List(communications) { comm in
                    LobbyistRow(comm: comm)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("lobbying.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard communications.isEmpty && !isLoading else { return }
        isLoading = true
        loadFailed = false
        // Capture primitive values on the main actor before crossing the boundary.
        let ln = member.lastName
        let fn = member.firstName
        let result = await LobbyistService.fetchCommunications(lastName: ln, firstName: fn)
        isLoading = false
        communications = result
        // fetchCommunications never throws; check the service's error flag to distinguish
        // a network failure from an MP who has no registered communications.
        if result.isEmpty {
            loadFailed = await LobbyistService.lastFetchFailed
        }
    }
}

// MARK: - Row

struct LobbyistRow: View {
    let comm: LobbyistCommunication

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comm.organizationName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            if !comm.subjectMatter.isEmpty {
                Text(comm.subjectMatter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                if let date = comm.communicationDate {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(comm.registrantType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Link(NSLocalizedString("lobbying.viewRecord", comment: ""), destination: comm.registryURL)
                .font(.caption2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [comm.organizationName]
        if !comm.subjectMatter.isEmpty { parts.append(comm.subjectMatter) }
        if let d = comm.communicationDate {
            parts.append(d.formatted(date: .long, time: .omitted))
        }
        parts.append(comm.registrantType)
        return parts.joined(separator: ", ")
    }
}
