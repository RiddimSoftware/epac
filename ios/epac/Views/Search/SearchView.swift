//
//  SearchView.swift
//  epac
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @EnvironmentObject var fetch: Fetch
    @Environment(\.modelContext) var modelContext
    @Environment(NavigationRouter.self) var router

    @Query(sort: [SortDescriptor(\Hansard.date, order: .reverse)])
    private var hansards: [Hansard]

    @Query(sort: \ParliamentMember.lastName)
    private var members: [ParliamentMember]

    @Query(sort: \RecordedVote.date, order: .reverse)
    private var votes: [RecordedVote]

    @State private var viewModel = SearchViewModel()
    @State private var bills: [Bill] = []
    @State private var selectedHansard: Hansard?
    @State private var selectedSubject: SubjectOfBusiness?
    @State private var selectedMember: ParliamentMember?

    private var results: SearchViewModel.SearchResults {
        viewModel.results(members: members, votes: votes, bills: bills, hansards: hansards)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isQueryTooShort {
                    promptView
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    resultsList
                }
            }
            .navigationTitle(NSLocalizedString("Search", comment: ""))
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("search.prompt", comment: "")
            )
            .navigationDestination(item: $selectedHansard) { hansard in
                SittingView(hansard: hansard, selectedSubject: $selectedSubject)
                    .navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
                    .navigationDestination(item: $selectedSubject) { subject in
                        SpeechView(hansard: hansard, subject: subject)
                    }
            }
            .navigationDestination(item: $selectedMember) { member in
                MemberProfileView(member: member)
            }
        }
        .task {
            if bills.isEmpty {
                bills = (try? await BillsService.fetchBills()) ?? []
            }
        }
        .environmentObject(fetch)
    }

    // MARK: - Subviews

    private var promptView: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: NSLocalizedString("search.prompt.title", comment: ""),
            message: NSLocalizedString("search.prompt.description", comment: ""),
            action: nil
        )
    }

    private var resultsList: some View {
        List {
            if !results.members.isEmpty {
                Section(NSLocalizedString("search.section.members", comment: "")) {
                    ForEach(results.members) { result in
                        Button {
                            selectedMember = result.member
                        } label: {
                            HStack(spacing: 10) {
                                MemberAvatar(member: result.member)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.member.name).font(.subheadline).foregroundStyle(.primary)
                                    Text("\(result.member.party.shortName) · \(result.member.riding)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityLabel(result.member.name)
                    }
                }
            }

            if !results.votes.isEmpty {
                Section(NSLocalizedString("search.section.votes", comment: "")) {
                    ForEach(results.votes) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if !result.vote.billNumberCode.isEmpty {
                                    Text(result.vote.billNumberCode)
                                        .font(.caption.bold())
                                        .foregroundStyle(.tint)
                                }
                                Text("Vote #\(result.vote.number)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(result.vote.resultEn)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.vote.descriptionEn)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(result.vote.date, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }


            if !results.bills.isEmpty {
                Section(NSLocalizedString("search.section.bills", comment: "")) {
                    ForEach(results.bills) { result in
                        NavigationLink(destination: BillDetailView(bill: result.bill)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.bill.number)
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.tint)
                                Text(result.bill.title).font(.subheadline).lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if !results.debates.isEmpty {
                Section(NSLocalizedString("search.section.debates", comment: "")) {
                    ForEach(results.debates) { result in
                        Button {
                            selectedSubject = result.subject
                            selectedHansard = result.hansard
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.subject.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(result.hansardDate.formatted(date: .long, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityLabel(result.subject.title)
                        .accessibilityHint(result.hansardDate.formatted(date: .long, time: .omitted))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
