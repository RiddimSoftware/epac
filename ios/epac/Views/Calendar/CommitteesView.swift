//
//  CommitteesView.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Displays standing committees, their recent meetings, and — when available —
//  individual interventions fetched from the OurCommons open API.
//
//  Architecture note: no ViewModel here. State is load-and-display with no
//  complex transformations; the @State + .task pattern is sufficient per CLAUDE.md.
//

import SwiftUI

// MARK: - Committees list

struct CommitteesView: View {
    @State private var committees: [ParliamentaryCommittee] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    /// Major standing committees surfaced first, in priority order.
    private let priorityAcronyms = ["FINA", "JUST", "HESA", "ENVI", "SECU", "PROC", "ETHI", "OGGO"]

    var featured: [ParliamentaryCommittee] {
        let priority = committees
            .filter { priorityAcronyms.contains($0.acronym) }
            .sorted {
                (priorityAcronyms.firstIndex(of: $0.acronym) ?? 99)
                    < (priorityAcronyms.firstIndex(of: $1.acronym) ?? 99)
            }
        let rest = committees
            .filter { !priorityAcronyms.contains($0.acronym) }
            .sorted { $0.name < $1.name }
        return priority + rest
    }

    var body: some View {
        Group {
            if isLoading && committees.isEmpty {
                ProgressView()
                    .accessibilityLabel(Text("Loading"))
            } else if loadFailed && committees.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("committees.error.title", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(NSLocalizedString("committees.error.description", comment: ""))
                )
            } else if committees.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("committees.empty.title", comment: ""),
                    systemImage: "person.3"
                )
            } else {
                List(featured) { committee in
                    NavigationLink(destination: CommitteeMeetingsView(committee: committee)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(committee.acronym)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.tint)
                            Text(committee.name)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityLabel("\(committee.acronym), \(committee.name)")
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("committees.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        guard committees.isEmpty else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        let result = await CommitteesService.fetchCommittees()
        if result.isEmpty {
            loadFailed = true
        } else {
            committees = result
        }
    }
}

// MARK: - Meetings for one committee

struct CommitteeMeetingsView: View {
    let committee: ParliamentaryCommittee
    @State private var meetings: [CommitteeMeeting] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading && meetings.isEmpty {
                ProgressView()
                    .accessibilityLabel(Text("Loading"))
            } else if loadFailed && meetings.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("committees.error.title", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(NSLocalizedString("committees.error.description", comment: ""))
                )
            } else if meetings.isEmpty && !isLoading {
                ContentUnavailableView(
                    NSLocalizedString("committees.noMeetings", comment: ""),
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                List(meetings) { meeting in
                    NavigationLink(destination: CommitteeEvidenceView(meeting: meeting)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(
                                    String(
                                        format: NSLocalizedString("committees.meeting.number", comment: ""),
                                        meeting.meetingNumber
                                    )
                                )
                                .font(.caption.monospacedDigit().weight(.semibold))
                                Spacer()
                                if let date = meeting.date {
                                    Text(date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let first = meeting.agendaItems.first {
                                Text(first)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .accessibilityLabel({
                        var label = String(
                            format: NSLocalizedString("committees.meeting.number", comment: ""),
                            meeting.meetingNumber
                        )
                        if let date = meeting.date {
                            label += ", \(date.formatted(date: .abbreviated, time: .omitted))"
                        }
                        if let first = meeting.agendaItems.first {
                            label += ", \(first)"
                        }
                        return label
                    }())
                }
                .listStyle(.plain)
                .refreshable {
                    meetings = []
                    loadFailed = false
                    await load()
                }
            }
        }
        .navigationTitle(committee.acronym)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        let result = await CommitteesService.fetchRecentMeetings(committeeId: committee.id)
        if result.isEmpty {
            loadFailed = true
        } else {
            meetings = result
        }
    }
}

// MARK: - Evidence (interventions) for one meeting

struct CommitteeEvidenceView: View {
    let meeting: CommitteeMeeting
    @State private var interventions: [CommitteeIntervention] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && interventions.isEmpty {
                ProgressView()
                    .accessibilityLabel(Text("Loading"))
            } else if interventions.isEmpty && !isLoading {
                // Evidence endpoint returned nothing — show metadata + link to source
                metadataFallback
            } else {
                List(interventions) { intervention in
                    InterventionRow(intervention: intervention)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(
            String(
                format: NSLocalizedString("committees.meeting.number", comment: ""),
                meeting.meetingNumber
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = ParlVULinkBuilder.committeeWatchURL(for: meeting) {
                    Link(destination: url) {
                        Image(systemName: "play.rectangle")
                    }
                    .accessibilityLabel(NSLocalizedString("committees.watchParlVU", comment: ""))
                } else {
                    Link(destination: ParlVULinkBuilder.committeeArchiveHomeURL) {
                        Image(systemName: "play.rectangle")
                    }
                    .accessibilityLabel(NSLocalizedString("committees.openParlVUArchive", comment: ""))
                }
            }
        }
    }

    @ViewBuilder
    private var metadataFallback: some View {
        List {
            if !meeting.agendaItems.isEmpty {
                Section(NSLocalizedString("committees.agenda", comment: "")) {
                    ForEach(meeting.agendaItems, id: \.self) { item in
                        Text(item).font(.subheadline)
                    }
                }
            }
            Section {
                if let url = ParlVULinkBuilder.committeeWatchURL(for: meeting) {
                    Link(destination: url) {
                        Label(
                            NSLocalizedString("committees.watchParlVU", comment: ""),
                            systemImage: "play.rectangle"
                        )
                    }
                    .foregroundStyle(.tint)
                } else {
                    Link(destination: ParlVULinkBuilder.committeeArchiveHomeURL) {
                        Label(
                            NSLocalizedString("committees.openParlVUArchive", comment: ""),
                            systemImage: "play.rectangle"
                        )
                    }
                    .foregroundStyle(.tint)
                }
            }
            if let url = meeting.publicationURL ?? meeting.evidenceURL {
                Section {
                    Link(
                        NSLocalizedString("committees.viewTranscript", comment: ""),
                        destination: url
                    )
                    .foregroundStyle(.tint)
                } footer: {
                    Text(NSLocalizedString("committees.transcript.source", comment: ""))
                        .font(.caption2)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        interventions = await CommitteesService.fetchInterventions(
            committeeId: meeting.committee,
            meetingNumber: meeting.meetingNumber
        )
    }
}

// MARK: - Intervention row

private struct InterventionRow: View {
    let intervention: CommitteeIntervention

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(intervention.speakerName)
                    .font(.subheadline.weight(.semibold))
                if intervention.isMP {
                    Text(NSLocalizedString("committees.mp", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                } else {
                    Text(NSLocalizedString("committees.witness", comment: ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !intervention.affiliation.isEmpty {
                Text(intervention.affiliation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(intervention.content)
                .font(.body)
                .lineLimit(6)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
