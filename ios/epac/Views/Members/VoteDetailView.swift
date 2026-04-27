//
//  VoteDetailView.swift
//  epac
//
//  Created by Sunny on 2026-04-27.
//

import SwiftUI
import SwiftData

private struct DebateSelection: Identifiable, Hashable {
    let id = UUID()
    let subject: SubjectOfBusiness
    let hansard: Hansard

    static func == (lhs: DebateSelection, rhs: DebateSelection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct VoteDetailView: View {
    let mv: MemberVote
    let rv: RecordedVote?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fetch: Fetch
    @State private var matchingSubjects: [(subject: SubjectOfBusiness, hansard: Hansard)] = []
    @State private var selectedDebate: DebateSelection?

    var body: some View {
        List {
            Section {
                voteMetadata
            }
            if !matchingSubjects.isEmpty {
                Section(header: Text(NSLocalizedString("voteDetail.debates.header", comment: ""))) {
                    ForEach(matchingSubjects, id: \.subject.hansardID) { pair in
                        Button {
                            selectedDebate = DebateSelection(subject: pair.subject, hansard: pair.hansard)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pair.subject.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Text(pair.hansard.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("\(pair.subject.title) — \(NSLocalizedString("voteDetail.seeDebate", comment: ""))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(rv.flatMap { $0.billNumberCode.isEmpty ? nil : $0.billNumberCode } ?? "Vote #\(mv.voteID)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedDebate) { selection in
            SpeechView(hansard: selection.hansard, subject: selection.subject)
        }
        .task { findMatchingDebates() }
    }

    @ViewBuilder
    private var voteMetadata: some View {
        if let rv {
            LabeledContent(NSLocalizedString("voteDetail.description", comment: ""), value: rv.descriptionEn)
            LabeledContent(NSLocalizedString("voteDetail.date", comment: ""), value: rv.date.formatted(.dateTime.day().month().year()))
            LabeledContent(NSLocalizedString("voteDetail.result", comment: ""), value: rv.resultEn)
            LabeledContent(
                NSLocalizedString("voteDetail.tally", comment: ""),
                value: "\(NSLocalizedString("votes.yea", comment: "")) \(rv.yea) — \(NSLocalizedString("votes.nay", comment: "")) \(rv.nay)"
            )
        }
        LabeledContent(NSLocalizedString("voteDetail.ballot", comment: ""), value: mv.recordedVote)
    }

    private func findMatchingDebates() {
        guard let bill = rv?.billNumberCode, !bill.isEmpty else { return }

        let allSubjects = (try? modelContext.fetch(FetchDescriptor<SubjectOfBusiness>())) ?? []
        let matched = allSubjects.filter { $0.title.localizedCaseInsensitiveContains(bill) }
        guard !matched.isEmpty else { return }

        var hansDescriptor = FetchDescriptor<Hansard>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        hansDescriptor.fetchLimit = 500
        let allHansards = (try? modelContext.fetch(hansDescriptor)) ?? []
        var results: [(subject: SubjectOfBusiness, hansard: Hansard)] = []
        for subject in matched {
            // Primary strategy: use Speech.date to find the parent Hansard
            if let speechDate = subject.speeches.first?.date,
               let hansard = allHansards.first(where: { Calendar.current.isDate($0.date, inSameDayAs: speechDate) }) {
                results.append((subject: subject, hansard: hansard))
                continue
            }
            // Fallback: match via OrderOfBusiness relationship
            if let hansard = allHansards.first(where: {
                $0.orders.contains(where: { $0.subjects.contains(where: { $0.hansardID == subject.hansardID }) })
            }) {
                results.append((subject: subject, hansard: hansard))
            }
        }
        matchingSubjects = results.sorted { $0.hansard.date > $1.hansard.date }
    }
}
