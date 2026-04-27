//
//  MyMPView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI
import SwiftData

// MARK: - Activity model

private enum MPActivity: Identifiable {
    case speech(Speech)
    case vote(MemberVote, RecordedVote?)
    case expenditure(SummaryExpenditure)

    var id: String {
        switch self {
        case .speech(let s):       return "speech-\(s.hansardID)"
        case .vote(let mv, _):     return "vote-\(mv.memberID)-\(mv.voteID)"
        case .expenditure(let e):  return "exp-\(e.firstName)-\(e.lastName)-\(e.year)-\(e.quarter)"
        }
    }

    var date: Date {
        switch self {
        case .speech(let s):
            return s.date
        case .vote(_, let rv):
            return rv?.date ?? .distantPast
        case .expenditure(let e):
            return Calendar.current.date(from: DateComponents(year: e.year, month: e.quarter * 3)) ?? .distantPast
        }
    }

    var systemImage: String {
        switch self {
        case .speech:       return "bubble.left.fill"
        case .vote:         return "checkmark.square.fill"
        case .expenditure:  return "dollarsign.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .speech:
            return .blue
        case .vote(let mv, _):
            switch mv.recordedVote.lowercased() {
            case "yea": return .green
            case "nay": return .red
            default:    return .orange
            }
        case .expenditure:
            return .teal
        }
    }

    var title: String {
        switch self {
        case .speech(let s):
            return s.title.isEmpty
                ? NSLocalizedString("myMP.activity.speech", comment: "")
                : s.title
        case .vote(let mv, let rv):
            let bill = (rv?.billNumberCode.isEmpty == false) ? rv!.billNumberCode : "Vote #\(mv.voteID)"
            return "\(bill) — \(mv.recordedVote)"
        case .expenditure(let e):
            return String(format: NSLocalizedString("myMP.activity.expenditure", comment: ""), e.year, e.quarter)
        }
    }
}

// MARK: - Activity row

private struct ActivityRow: View {
    let activity: MPActivity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.systemImage)
                .foregroundStyle(activity.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.subheadline)
                    .lineLimit(2)
                if activity.date > Date.distantPast {
                    Text(activity.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - MyMPView

struct MyMPView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var member: ParliamentMember?
    @State private var activities: [MPActivity] = []
    @State private var isLoading = false
    @State private var showPostalCodeSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if PostalCodeViewModel.savedMemberName == nil {
                    noMPSetView
                } else if isLoading && activities.isEmpty {
                    ProgressView()
                } else if activities.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("myMP.empty.title", comment: ""),
                        systemImage: "person.fill.viewfinder",
                        description: Text(NSLocalizedString("myMP.empty.description", comment: ""))
                    )
                } else {
                    activityList
                }
            }
            .navigationTitle(PostalCodeViewModel.savedMemberName ?? NSLocalizedString("myMP.navTitle", comment: ""))
            .task { await loadActivities() }
        }
        .sheet(isPresented: $showPostalCodeSetup) {
            PostalCodeSetupView { showPostalCodeSetup = false }
        }
    }

    // MARK: - Subviews

    private var noMPSetView: some View {
        ContentUnavailableView {
            Label(NSLocalizedString("myMP.noMP.title", comment: ""), systemImage: "person.fill.viewfinder")
        } description: {
            Text(NSLocalizedString("myMP.noMP.description", comment: ""))
        } actions: {
            Button(NSLocalizedString("riding.setup.lookupButton", comment: "")) {
                showPostalCodeSetup = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var activityList: some View {
        List(activities) { activity in
            ActivityRow(activity: activity)
        }
        .listStyle(.plain)
    }

    // MARK: - Data loading

    @MainActor
    private func loadActivities() async {
        isLoading = true
        defer { isLoading = false }

        guard let memberName = PostalCodeViewModel.savedMemberName else { return }

        // Resolve ParliamentMember
        let members = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
        guard let mp = members.first(where: {
            $0.name.localizedCaseInsensitiveContains(memberName) ||
            memberName.localizedCaseInsensitiveContains($0.lastName)
        }) else { return }
        member = mp

        var all: [MPActivity] = []

        // Speeches: filter speeches where at least one message matches the MP's name
        let speeches = (try? modelContext.fetch(FetchDescriptor<Speech>())) ?? []
        let mpFirstName = mp.firstName
        let mpLastName = mp.lastName
        let mySpeeches = speeches.filter { speech in
            speech.messages.contains {
                $0.lastName.localizedCaseInsensitiveCompare(mpLastName) == .orderedSame &&
                $0.firstName.localizedCaseInsensitiveContains(String(mpFirstName.prefix(3)))
            }
        }
        all += mySpeeches.map { .speech($0) }

        // Votes: predicate on memberID
        let mid = mp.memberID
        let votes = (try? modelContext.fetch(FetchDescriptor<MemberVote>(
            predicate: #Predicate { $0.memberID == mid }
        ))) ?? []
        all += votes.map { mv in .vote(mv, mv.vote) }

        // Expenditures: match by last name and first-name prefix
        let exps = (try? modelContext.fetch(FetchDescriptor<SummaryExpenditure>())) ?? []
        let firstThree = String(mpFirstName.prefix(3))
        let myExps = exps.filter {
            $0.lastName.localizedCaseInsensitiveCompare(mpLastName) == .orderedSame &&
            $0.firstName.localizedCaseInsensitiveContains(firstThree)
        }
        all += myExps.map { .expenditure($0) }

        activities = all.sorted { $0.date > $1.date }
    }
}
