// WrittenQuestionsSection.swift
// epac
//
// Collapsed disclosure section showing written questions (Questions on the Order Paper)
// submitted by an MP. Data from api.open.ourcommons.ca. Overdue questions (no response
// after 45 days) shown with a distinct badge per Parliament of Canada convention.

import SwiftData
import SwiftUI

struct WrittenQuestionsSection: View {
    let member: ParliamentMember

    @Query private var questions: [WrittenQuestion]
    @State private var isExpanded = false

    init(member: ParliamentMember) {
        self.member = member
        let id = member.memberID
        _questions = Query(
            filter: #Predicate<WrittenQuestion> { $0.memberID == id },
            sort: [SortDescriptor(\WrittenQuestion.dateSubmitted, order: .reverse)]
        )
    }

    var body: some View {
        if !questions.isEmpty {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(questions.prefix(5)) { question in
                            WrittenQuestionRow(question: question)
                        }
                        if questions.count > 5 {
                            Text("\(questions.count - 5) more questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.tint)
                        Text("Written Questions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        let overdueCount = questions.filter(\.isOverdue).count
                        if overdueCount > 0 {
                            Text("\(overdueCount) unanswered")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.appWarning)
                                .clipShape(Capsule())
                        }
                    }
                }
            )
            .padding()
            .background(Color.appSurface)
            .cornerRadius(12)
        }
    }
}

private struct WrittenQuestionRow: View {
    let question: WrittenQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Q-\(question.number)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }
            if !question.subject.isEmpty {
                Text(question.subject)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Text(question.questionTextEn)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(question.dateSubmitted, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if question.isOverdue {
            Text("Overdue")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.appWarning)
                .clipShape(Capsule())
        } else if question.responseTextEn != nil {
            Text("Answered")
                .font(.caption2.bold())
                .foregroundStyle(Color.appPositive)
        } else {
            Text("Pending")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
