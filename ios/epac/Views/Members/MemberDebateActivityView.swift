//
//  MemberDebateActivityView.swift
//  epac
//

import SwiftUI
import SwiftData

// Speech feed for a member's profile (EPAC-299).
// Shows every speech this MP has given, most recent first, with topic filters
// and a stats bar. Data comes from GET /api/v1/members/{id}/speeches (EPAC-293).
struct MemberDebateActivityView: View {
    let member: ParliamentMember

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fetch: Fetch
    @State private var viewModel: MemberSpeechFeedViewModel

    init(member: ParliamentMember) {
        self.member = member
        self._viewModel = State(wrappedValue: MemberSpeechFeedViewModel(memberId: member.memberID))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.speeches.isEmpty {
                loadingView
            } else if let err = viewModel.error, viewModel.speeches.isEmpty {
                errorView(message: err)
            } else if viewModel.speeches.isEmpty {
                emptyView
            } else {
                feedList
            }
        }
        .navigationTitle("Speeches")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.speeches.isEmpty {
                await viewModel.loadInitial()
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading speeches…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Couldn't load speeches")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadInitial() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No speeches found")
                .font(.headline)
            if viewModel.selectedTopic != nil {
                Text("No speeches match this topic filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Clear filter") {
                    Task { await viewModel.applyTopicFilter(nil) }
                }
                .buttonStyle(.bordered)
            } else {
                Text("No speeches from this Parliament have been indexed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Feed

    private var feedList: some View {
        List {
            // Stats bar
            if let s = viewModel.stats {
                Section {
                    statsBar(stats: s)
                }
            }

            // Topic filter chips
            if !viewModel.topicChips.isEmpty {
                Section {
                    topicFilterRow
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Speech entries
            Section {
                ForEach(viewModel.speeches) { entry in
                    SpeechEntryRow(entry: entry, member: member)
                        .task {
                            await viewModel.loadMoreIfNeeded(currentItem: entry)
                        }
                }
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadInitial()
        }
    }

    // MARK: - Stats bar

    private func statsBar(stats: MemberStats) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(stats.totalSpeeches)", label: "Speeches")
            Divider().frame(height: 40)
            statCell(value: "\(stats.avgWordCount)", label: "Avg words")
            if !stats.topTopic.isEmpty {
                Divider().frame(height: 40)
                statCell(value: stats.topTopic, label: "Most on", compact: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stats.totalSpeeches) speeches, \(stats.avgWordCount) average words, most frequent topic: \(stats.topTopic)")
    }

    private func statCell(value: String, label: String, compact: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(compact ? .caption.bold() : .title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Topic filter chips

    private var topicFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", isSelected: viewModel.selectedTopic == nil) {
                    Task { await viewModel.applyTopicFilter(nil) }
                }
                ForEach(viewModel.topicChips) { chip in
                    chipButton(
                        label: "\(chip.id) (\(chip.count))",
                        isSelected: viewModel.selectedTopic == chip.id
                    ) {
                        Task {
                            let newTopic = viewModel.selectedTopic == chip.id ? nil : chip.id
                            await viewModel.applyTopicFilter(newTopic)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Speech entry row

struct SpeechEntryRow: View {
    let entry: MemberSpeechEntry
    let member: ParliamentMember

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fetch: Fetch
    @State private var isNavigating = false
    @State private var targetHansard: Hansard?
    @State private var targetSubject: SubjectOfBusiness?

    var body: some View {
        Button {
            Task { await navigateToSpeech() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if let date = entry.parsedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let words = entry.wordCount, words > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(words) words")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isNavigating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let subject = entry.subjectTitle, !subject.isEmpty {
                    Text(subject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }

                if !entry.preview.isEmpty {
                    Text(entry.preview + "…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .navigationDestination(item: $targetHansard) { hansard in
            if let subject = targetSubject {
                SpeechView(hansard: hansard, subject: subject)
                    .environmentObject(fetch)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let subject = entry.subjectTitle { parts.append(subject) }
        if let date = entry.parsedDate {
            parts.append("on " + date.formatted(date: .long, time: .omitted))
        }
        if let words = entry.wordCount { parts.append("\(words) words") }
        return parts.joined(separator: ", ")
    }

    private func navigateToSpeech() async {
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }

        guard let sittingDate = entry.parsedDate else { return }

        if let hansard = findHansard(for: sittingDate) {
            if let subject = findSubject(in: hansard, interventionId: entry.id) {
                targetSubject = subject
                targetHansard = hansard
            } else if let first = hansard.orders.first?.subjects.first {
                targetSubject = first
                targetHansard = hansard
            }
        } else {
            try? await fetch.downloadHansard(sittingDate)
            if let hansard = findHansard(for: sittingDate) {
                targetSubject = hansard.orders.first?.subjects.first
                targetHansard = hansard
            }
        }
    }

    private func findHansard(for date: Date) -> Hansard? {
        let cal = Calendar.current
        let target = cal.startOfDay(for: date)
        guard let nextDay = cal.date(byAdding: .day, value: 1, to: target) else { return nil }
        let descriptor = FetchDescriptor<Hansard>(
            predicate: #Predicate { hansard in
                hansard.date >= target && hansard.date < nextDay
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func findSubject(in hansard: Hansard, interventionId: String) -> SubjectOfBusiness? {
        for order in hansard.orders {
            for subject in order.subjects {
                for speech in subject.speeches {
                    if speech.messages.contains(where: { $0.hansardID == interventionId }) {
                        return subject
                    }
                }
            }
        }
        return nil
    }
}
