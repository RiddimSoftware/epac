//
//  VoteDetailView.swift
//  epac
//
//  Created by Sunny on 2026-04-27.
//

import SwiftUI
import SwiftData

struct VoteDetailView: View {
    let mv: MemberVote
    let rv: RecordedVote?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fetch: Fetch
    @State private var matchingSubjects: [(subject: SubjectOfBusiness, hansard: Hansard)] = []
    @State private var selectedSubject: SubjectOfBusiness?
    @State private var selectedHansard: Hansard?

    var body: some View {
        List {
            Section {
                voteMetadata
            }
            if !matchingSubjects.isEmpty {
                Section(header: Text(NSLocalizedString("voteDetail.debates.header", comment: ""))) {
                    ForEach(matchingSubjects, id: \.subject.hansardID) { pair in
                        Button {
                            selectedSubject = pair.subject
                            selectedHansard = pair.hansard
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
        .navigationTitle(rv?.billNumberCode.isEmpty == false ? rv!.billNumberCode : "Vote #\(mv.voteID)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedSubject) { subject in
            if let hansard = selectedHansard {
                SpeechView(hansard: hansard, subject: subject)
            }
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

        let allHansards = (try? modelContext.fetch(FetchDescriptor<Hansard>())) ?? []
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
