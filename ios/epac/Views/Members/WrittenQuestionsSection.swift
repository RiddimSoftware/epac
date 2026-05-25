// WrittenQuestionsSection.swift
// epac
//
// Collapsed disclosure section showing written questions (Questions on the Order Paper)
// submitted by an MP. Data from our data source links (openparliament.ca). Overdue questions (no response
// after 45 days) shown with a distinct badge per Parliament of Canada convention.

import SwiftData
import SwiftUI

private enum WrittenQuestionsLayout {
    static let sectionSpacing: CGFloat = 12
    static let previewLimit = 5
    static let contentTopPadding = EpacSpacing.s
    static let badgeHorizontalPadding = EpacSpacing.s
    static let badgeVerticalPadding = EpacSpacing.xxs
    static let cardCornerRadius = EpacCornerRadius.m
    static let rowSpacing = EpacSpacing.xs
    static let subjectLineLimit = 2
    static let questionLineLimit = 3
    static let rowVerticalPadding = EpacSpacing.xs
    static let statusHorizontalPadding: CGFloat = 6
}

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
                    VStack(alignment: .leading, spacing: WrittenQuestionsLayout.sectionSpacing) {
                        ForEach(questions.prefix(WrittenQuestionsLayout.previewLimit)) { question in
                            WrittenQuestionRow(question: question)
                        }
                        if questions.count > WrittenQuestionsLayout.previewLimit {
                            Text("\(questions.count - WrittenQuestionsLayout.previewLimit) more questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, WrittenQuestionsLayout.contentTopPadding)
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
                                .padding(.horizontal, WrittenQuestionsLayout.badgeHorizontalPadding)
                                .padding(.vertical, WrittenQuestionsLayout.badgeVerticalPadding)
                                .background(Color.appWarning)
                                .clipShape(Capsule())
                        }
                    }
                }
            )
            .padding()
            .background(Color.appSurface)
            .cornerRadius(WrittenQuestionsLayout.cardCornerRadius)
        }
    }
}

private struct WrittenQuestionRow: View {
    let question: WrittenQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: WrittenQuestionsLayout.rowSpacing) {
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
                    .lineLimit(WrittenQuestionsLayout.subjectLineLimit)
            }
            Text(question.questionTextEn)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(WrittenQuestionsLayout.questionLineLimit)
            Text(question.dateSubmitted, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, WrittenQuestionsLayout.rowVerticalPadding)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if question.isOverdue {
            Text("Overdue")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, WrittenQuestionsLayout.statusHorizontalPadding)
                .padding(.vertical, WrittenQuestionsLayout.badgeVerticalPadding)
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
