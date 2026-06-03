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

private enum CommitteesLayout {
    static let priorityFallbackIndex = 99
    static let loadingSpacing = EpacSpacing.m
    static let sourceRowSpacing: CGFloat = 12
    static let sourceIconWidth: CGFloat = 28
    static let compactTextSpacing: CGFloat = 3
    static let rowVerticalPadding = EpacSpacing.xxs
    static let rowLineLimit = 2
    static let meetingRowSpacing: CGFloat = 5
    static let meetingDateSpacing: CGFloat = 1
    static let meetingVerticalPadding: CGFloat = 3
    static let witnessPreviewLimit = 3
    static let summaryTopPadding = EpacSpacing.xs
    static let digestTextSpacing: CGFloat = 3
    static let interventionSpacing: CGFloat = 6
    static let interventionBadgeSpacing: CGFloat = 6
    static let interventionBadgeHorizontalPadding: CGFloat = 5
    static let interventionBadgeVerticalPadding = EpacSpacing.xxs
    static let interventionLineLimit = 6
    static let interventionVerticalPadding: CGFloat = 6
}

// MARK: - Committees list

struct CommitteesView: View {
    @State private var committees: [ParliamentaryCommittee] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @Environment(\.openURL) private var openURL

    /// Major standing committees surfaced first, in priority order.
    private let priorityAcronyms = ["FINA", "JUST", "HESA", "ENVI", "SECU", "PROC", "ETHI", "OGGO"]

    /// Senate of Canada committees landing page on sencanada.ca. The Senate
    /// publishes its own evidence and reports outside the OurCommons open API;
    /// Phase 2 ingests this data, Phase 1 deep-links to the source.
    private static let senateCommitteesURL = URL(string: "https://sencanada.ca/en/committees/")!

    var featured: [ParliamentaryCommittee] {
        let priority = committees
            .filter { priorityAcronyms.contains($0.acronym) }
            .sorted {
                (priorityAcronyms.firstIndex(of: $0.acronym) ?? CommitteesLayout.priorityFallbackIndex)
                    < (priorityAcronyms.firstIndex(of: $1.acronym) ?? CommitteesLayout.priorityFallbackIndex)
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
                VStack(spacing: CommitteesLayout.loadingSpacing) {
                    ContentUnavailableView(
                        NSLocalizedString("committees.error.title", comment: ""),
                        systemImage: "exclamationmark.triangle",
                        description: Text(NSLocalizedString("committees.error.description", comment: ""))
                    )
                    Button(NSLocalizedString("committees.retry", comment: "")) {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if committees.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("committees.empty.title", comment: ""),
                    systemImage: "person.3"
                )
            } else {
                List {
                    Section {
                        Button {
                            openURL(Self.senateCommitteesURL)
                        } label: {
                            HStack(spacing: CommitteesLayout.sourceRowSpacing) {
                                Image(systemName: "building.columns.circle.fill")
                                    .foregroundStyle(.red)
                                    .frame(width: CommitteesLayout.sourceIconWidth)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: CommitteesLayout.compactTextSpacing) {
                                    Text("Senate Committees")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text("Evidence, reports, and witness lists from sencanada.ca")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, CommitteesLayout.rowVerticalPadding)
                        }
                        .accessibilityLabel("Senate Committees, opens sencanada.ca in Safari")
                    } header: {
                        Text("Senate of Canada")
                    } footer: {
                        Text("Source: Senate of Canada. Senate committees publish their own verbatim evidence and reports; the link opens the Senate's official committees portal.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(featured) { committee in
                            NavigationLink(destination: CommitteeMeetingsView(committee: committee)) {
                                VStack(alignment: .leading, spacing: CommitteesLayout.compactTextSpacing) {
                                    Text(committee.acronym)
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.tint)
                                    Text(committee.name)
                                        .font(.subheadline)
                                        .lineLimit(CommitteesLayout.rowLineLimit)
                                }
                                .padding(.vertical, CommitteesLayout.rowVerticalPadding)
                            }
                            .accessibilityLabel("\(committee.acronym), \(committee.name)")
                        }
                    } header: {
                        Text("House of Commons")
                    }
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
    @State private var upcomingMeetings: [CommitteeMeeting] = []
    @State private var recentMeetings: [CommitteeMeeting] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    private var hasMeetings: Bool {
        !upcomingMeetings.isEmpty || !recentMeetings.isEmpty
    }

    var body: some View {
        Group {
            if isLoading && !hasMeetings {
                ProgressView()
                    .accessibilityLabel(Text("Loading"))
            } else if loadFailed && !hasMeetings {
                VStack(spacing: CommitteesLayout.loadingSpacing) {
                    ContentUnavailableView(
                        NSLocalizedString("committees.error.title", comment: ""),
                        systemImage: "exclamationmark.triangle",
                        description: Text(NSLocalizedString("committees.error.description", comment: ""))
                    )
                    Button(NSLocalizedString("committees.retry", comment: "")) {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if !hasMeetings && !isLoading {
                ContentUnavailableView(
                    NSLocalizedString("committees.noMeetings", comment: ""),
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                List {
                    if !upcomingMeetings.isEmpty {
                        Section(NSLocalizedString("committees.upcoming", comment: "")) {
                            ForEach(upcomingMeetings) { meeting in
                                NavigationLink(destination: CommitteeEvidenceView(meeting: meeting)) {
                                    CommitteeMeetingRow(meeting: meeting, showsWitnesses: true)
                                }
                                .accessibilityLabel(accessibilityLabel(for: meeting))
                            }
                        }
                    }

                    if !recentMeetings.isEmpty {
                        Section(NSLocalizedString("committees.recentEvidence", comment: "")) {
                            ForEach(recentMeetings) { meeting in
                                NavigationLink(destination: CommitteeEvidenceView(meeting: meeting)) {
                                    CommitteeMeetingRow(meeting: meeting, showsWitnesses: false)
                                }
                                .accessibilityLabel(accessibilityLabel(for: meeting))
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    upcomingMeetings = []
                    recentMeetings = []
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
        let result = await CommitteesService.fetchMeetings(committeeId: committee.id)
        if result.upcoming.isEmpty && result.recent.isEmpty {
            loadFailed = true
        } else {
            upcomingMeetings = result.upcoming
            recentMeetings = result.recent
        }
    }

    private func accessibilityLabel(for meeting: CommitteeMeeting) -> String {
        var label = String(
            format: NSLocalizedString("committees.meeting.number", comment: ""),
            meeting.meetingNumber
        )
        if let date = meeting.date {
            label += ", \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        if let first = meeting.agendaItems.first {
            label += ", \(first)"
        }
        if !meeting.witnesses.isEmpty {
            label += ", "
            label += String(
                format: NSLocalizedString("committees.witnesses.accessibility.count", comment: ""),
                meeting.witnesses.count
            )
        }
        return label
    }
}

private struct CommitteeMeetingRow: View {
    let meeting: CommitteeMeeting
    let showsWitnesses: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CommitteesLayout.meetingRowSpacing) {
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
                    VStack(alignment: .trailing, spacing: CommitteesLayout.meetingDateSpacing) {
                        Text(date, style: .date)
                            .font(.caption2)
                        Text(date, style: .time)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if let first = meeting.agendaItems.first {
                Text(first)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(CommitteesLayout.rowLineLimit)
            }
            if showsWitnesses, !meeting.witnesses.isEmpty {
                Text(witnessSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(CommitteesLayout.rowLineLimit)
            }
        }
        .padding(.vertical, CommitteesLayout.meetingVerticalPadding)
    }

    private var witnessSummary: String {
        let names = meeting.witnesses.prefix(CommitteesLayout.witnessPreviewLimit).map(\.name).joined(separator: ", ")
        if meeting.witnesses.count > CommitteesLayout.witnessPreviewLimit {
            return String(
                format: NSLocalizedString("committees.witnesses.count", comment: ""),
                names,
                meeting.witnesses.count - CommitteesLayout.witnessPreviewLimit
            )
        }
        return String(format: NSLocalizedString("committees.witnesses", comment: ""), names)
    }
}

// MARK: - Evidence (interventions) for one meeting

struct CommitteeEvidenceView: View {
    let meeting: CommitteeMeeting
    @State private var interventions: [CommitteeIntervention] = []
    @State private var witnessDigests: [CommitteeWitnessDigest] = []
    @State private var hearingOverview: String?
    @State private var isLoading = false
    @State private var isGeneratingDigests = false
    @State private var isGeneratingOverview = false
    @State private var summaryError: String?

    var body: some View {
        Group {
            if isLoading && interventions.isEmpty {
                ProgressView()
                    .accessibilityLabel(Text("Loading"))
            } else if interventions.isEmpty && !isLoading {
                // Evidence endpoint returned nothing — show metadata + link to source
                metadataFallback
            } else {
                List {
                    if CommitteeSummaryService.isAvailable {
                        summarySection
                    }
                    Section("Transcript") {
                        ForEach(interventions) { intervention in
                            InterventionRow(intervention: intervention)
                        }
                    }
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
    private var summarySection: some View {
        Section {
            if isGeneratingDigests {
                HStack {
                    ProgressView()
                    Text("Generating witness digests...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !witnessDigests.isEmpty {
                ForEach(witnessDigests) { digest in
                    DisclosureGroup {
                        Text(digest.summary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.top, CommitteesLayout.summaryTopPadding)
                    } label: {
                        VStack(alignment: .leading, spacing: CommitteesLayout.digestTextSpacing) {
                            Text(digest.witnessName)
                                .font(.subheadline.weight(.semibold))
                            if !digest.affiliation.isEmpty {
                                Text(digest.affiliation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(digest.interventionCount) intervention\(digest.interventionCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let hearingOverview {
                    DisclosureGroup("Hearing overview") {
                        Text(hearingOverview)
                            .font(.subheadline)
                            .padding(.top, CommitteesLayout.summaryTopPadding)
                    }
                }

                Button {
                    Task { await generateHearingOverview() }
                } label: {
                    if isGeneratingOverview {
                        Label("Summarizing hearing...", systemImage: "sparkles")
                    } else {
                        Label("Summarize this hearing", systemImage: "sparkles")
                    }
                }
                .disabled(isGeneratingOverview)
            }

            if let summaryError {
                Text(summaryError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Committee digest")
        } footer: {
            Text(CommitteeSummaryService.label)
                .font(.caption2)
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
            if !meeting.witnesses.isEmpty {
                Section(NSLocalizedString("committees.confirmedWitnesses", comment: "")) {
                    ForEach(meeting.witnesses) { witness in
                        VStack(alignment: .leading, spacing: CommitteesLayout.compactTextSpacing) {
                            Text(witness.name)
                                .font(.subheadline.weight(.semibold))
                            if !witness.organization.isEmpty {
                                NavigationLink(destination: LobbyistOrganizationView(organizationName: witness.organization)) {
                                    Text(witness.organization)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
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
        await generateWitnessDigestsIfNeeded()
    }

    private func generateWitnessDigestsIfNeeded() async {
        guard CommitteeSummaryService.isAvailable,
              !interventions.isEmpty,
              witnessDigests.isEmpty,
              !isGeneratingDigests else {
            return
        }

        isGeneratingDigests = true
        summaryError = nil
        defer { isGeneratingDigests = false }

        do {
            witnessDigests = try await CommitteeSummaryService.shared.witnessDigests(
                for: meeting,
                interventions: interventions
            )
        } catch CommitteeSummaryServiceError.noWitnessInterventions {
            summaryError = "No witness testimony available to summarize."
        } catch {
            summaryError = "Committee digest unavailable."
        }
    }

    private func generateHearingOverview() async {
        guard CommitteeSummaryService.isAvailable, !interventions.isEmpty else { return }

        isGeneratingOverview = true
        summaryError = nil
        defer { isGeneratingOverview = false }

        do {
            hearingOverview = try await CommitteeSummaryService.shared.hearingOverview(
                for: meeting,
                interventions: interventions
            )
        } catch {
            summaryError = "Hearing overview unavailable."
        }
    }
}

// MARK: - Intervention row

private struct InterventionRow: View {
    let intervention: CommitteeIntervention

    var body: some View {
        VStack(alignment: .leading, spacing: CommitteesLayout.interventionSpacing) {
            HStack(spacing: CommitteesLayout.interventionBadgeSpacing) {
                Text(intervention.speakerName)
                    .font(.subheadline.weight(.semibold))
                if intervention.isMP {
                    Text(NSLocalizedString("committees.mp", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, CommitteesLayout.interventionBadgeHorizontalPadding)
                        .padding(.vertical, CommitteesLayout.interventionBadgeVerticalPadding)
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
                .lineLimit(CommitteesLayout.interventionLineLimit)
        }
        .padding(.vertical, CommitteesLayout.interventionVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}
