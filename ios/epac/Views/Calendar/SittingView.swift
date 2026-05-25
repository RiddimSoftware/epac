//
//  SittingView.swift
//  epac
//
//  Created by Sunny on 2024-12-13.
//

import SwiftData
import SwiftUI

private enum SittingViewLayout {
	static let listRowTopInset: CGFloat = 12
	static let listRowHorizontalInset = EpacSpacing.m
	static let listRowBottomInset = EpacSpacing.xs
	static var oralQuestionsInsets: EdgeInsets {
		EdgeInsets(
			top: listRowTopInset,
			leading: listRowHorizontalInset,
			bottom: listRowBottomInset,
			trailing: listRowHorizontalInset
		)
	}
	static let subjectSpacing = EpacSpacing.s
	static let speakerStackSpacing = EpacSpacing.xs
	static let subjectVerticalPadding = EpacSpacing.xs
	static let headerTopPadding: CGFloat = 20
	static let headerBottomPadding = EpacSpacing.s
	static let oralCardSpacing: CGFloat = 14
	static let oralCardContentVerticalPadding = EpacSpacing.xxs
	static let oralCardPadding = EpacSpacing.m
	static let oralCardCornerRadius = EpacCornerRadius.s
	static let oralCardBorderOpacity = 0.22
	static let oralHeaderSpacing = EpacSpacing.xs
	static let partyGroupSpacing = EpacSpacing.s
	static let partyHeaderSpacing: CGFloat = 6
	static let partyIconSize: CGFloat = 18
	static let partyIconPadding = EpacSpacing.xxs
	static let questionRowSpacing: CGFloat = 10
	static let questionTextSpacing: CGFloat = 5
	static let questionFirstLineTopPadding = EpacSpacing.xxs
	static let questionSpacerLength = EpacSpacing.s
	static let questionChevronTopPadding = EpacSpacing.xs
	static let questionVerticalPadding = EpacSpacing.s
	static let speakerRowSpacing: CGFloat = 6
	static let speakerIconSize = EpacIconSize.xs
	static let speakerIconPadding = EpacSpacing.xxs
	static let highlightBorderWidth: CGFloat = 2
	static let highlightCornerRadius = EpacCornerRadius.s
	static let highlightOpacity = 0.18
	static let scrollDelaySeconds = 0.3
}

struct SittingView: View {

	@Environment(\.modelContext) var modelContext

	@EnvironmentObject var fetch: Fetch

	let hansard: Hansard

	@Binding var selectedSubject: SubjectOfBusiness?
	var initialInterventionID: String?

	@Query var members: [ParliamentMember]

	@State private var coordinator = MemberDownloadCoordinator()
	@State private var viewModel = SittingViewModel()
	@State private var highlightedSubjectHansardID: String?

	var body: some View {
		let pairs = viewModel.visibleOrderSubjects(from: hansard)
		let oralQuestions = viewModel.oralQuestionsSummary(from: hansard)
		Group {
			if pairs.isEmpty && !viewModel.searchText.isEmpty {
				ContentUnavailableView.search(text: viewModel.searchText)
			} else {
				ScrollViewReader { proxy in
					List {
						if let oralQuestions {
							OralQuestionsCard(summary: oralQuestions) { question in
								viewModel.prepareNavigation(to: question)
								selectedSubject = question.subject
							}
							.listRowSeparator(.hidden)
							.listRowInsets(SittingViewLayout.oralQuestionsInsets)
						}
						ForEach(pairs, id: \.order.hansardID) { (order, subjects) in
							Section {
								ForEach(subjects) { subject in
									let isHighlighted = subject.hansardID == highlightedSubjectHansardID
									VStack(alignment: .leading, spacing: SittingViewLayout.subjectSpacing) {
										Text(subject.title)
											.font(.headline)
											.foregroundColor(.primary)

										HStack {
											Spacer()
											VStack(alignment: .trailing, spacing: SittingViewLayout.speakerStackSpacing) {
												ForEach(coordinator.speakers(for: subject, from: members, fetch: fetch)) { member in
													SittingSpeakerView(member: member)
												}
											}
										}
									}
									.padding(.vertical, SittingViewLayout.subjectVerticalPadding)
									.background(
										isHighlighted
											? RoundedRectangle(cornerRadius: SittingViewLayout.highlightCornerRadius)
												.fill(Color.accentColor.opacity(SittingViewLayout.highlightOpacity))
												.overlay(
													RoundedRectangle(cornerRadius: SittingViewLayout.highlightCornerRadius)
														.stroke(Color.accentColor, lineWidth: SittingViewLayout.highlightBorderWidth)
												)
											: nil
									)
									.id(subject.hansardID)
									.contentShape(Rectangle())
									.accessibilityElement(children: .ignore)
									.accessibilityLabel(subject.title)
									.accessibilityHint("Open debate")
									.accessibilityAddTraits(.isButton)
									.onTapGesture {
										selectedSubject = subject
									}
								}
							} header: {
								Text(order.catchline)
									.font(.title2)
									.fontWeight(.black)
									.textCase(.uppercase)
									.foregroundColor(.secondary)
									.padding(.top, SittingViewLayout.headerTopPadding)
									.padding(.bottom, SittingViewLayout.headerBottomPadding)
							}
						}
					}
					.listStyle(.plain)
					.onAppear {
						resolveAndScrollToIntervention(proxy: proxy, fallbackSubjectID: pairs.first?.1.first?.hansardID)
					}
				}
			}
		}
		.searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search debates")
	}

	private func resolveAndScrollToIntervention(proxy: ScrollViewProxy, fallbackSubjectID: String?) {
		guard let interventionID = initialInterventionID else { return }

		let targetSubjectID = hansard.orders
			.flatMap(\.subjects)
			.first { subject in
				subject.speeches.contains { speech in
					speech.hansardID == interventionID || speech.messages.contains { $0.hansardID == interventionID }
				}
			}?.hansardID

		guard let targetSubjectID else {
			highlightedSubjectHansardID = nil
			scrollToSubject(fallbackSubjectID, anchor: .top, with: proxy)
			return
		}

		highlightedSubjectHansardID = targetSubjectID
		scrollToSubject(targetSubjectID, anchor: .center, with: proxy)
	}

	private func scrollToSubject(_ subjectID: String?, anchor: UnitPoint, with proxy: ScrollViewProxy) {
		guard let subjectID else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + SittingViewLayout.scrollDelaySeconds) {
			withAnimation {
				proxy.scrollTo(subjectID, anchor: anchor)
			}
		}
	}
}

private struct OralQuestionsCard: View {
	let summary: OralQuestionSummary
	let onSelect: (OralQuestion) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: SittingViewLayout.oralCardSpacing) {
			header
			ScrollView {
				LazyVStack(alignment: .leading, spacing: SittingViewLayout.oralCardSpacing) {
					ForEach(summary.groups) { group in
						partyGroup(group)
					}
				}
				.padding(.vertical, SittingViewLayout.oralCardContentVerticalPadding)
			}
		}
		.padding(SittingViewLayout.oralCardPadding)
		.background(
			RoundedRectangle(cornerRadius: SittingViewLayout.oralCardCornerRadius)
				.fill(Color(uiColor: .secondarySystemGroupedBackground))
		)
		.overlay(
			RoundedRectangle(cornerRadius: SittingViewLayout.oralCardCornerRadius)
				.stroke(Color.accentColor.opacity(SittingViewLayout.oralCardBorderOpacity), lineWidth: 1)
		)
		.accessibilityElement(children: .contain)
	}

	private var header: some View {
		HStack(alignment: .firstTextBaseline) {
			VStack(alignment: .leading, spacing: SittingViewLayout.oralHeaderSpacing) {
				Label(NSLocalizedString("sitting.oralQuestions.title", comment: ""), systemImage: "questionmark.bubble.fill")
					.font(.headline)
				Text(String(format: NSLocalizedString("sitting.oralQuestions.count", comment: ""), summary.totalQuestions))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
	}

	private func partyGroup(_ group: OralQuestionGroup) -> some View {
		VStack(alignment: .leading, spacing: SittingViewLayout.partyGroupSpacing) {
			HStack(spacing: SittingViewLayout.partyHeaderSpacing) {
				if let image = group.party.image {
					Image(uiImage: image)
						.resizable()
						.scaledToFit()
						.frame(width: SittingViewLayout.partyIconSize, height: SittingViewLayout.partyIconSize)
						.padding(SittingViewLayout.partyIconPadding)
						.background(Circle().fill(Color.white).shadow(radius: 1))
				}
				Text(group.party.shortName)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
			}
			ForEach(group.questions) { question in
				OralQuestionRow(question: question) {
					onSelect(question)
				}
			}
		}
	}
}

private struct OralQuestionRow: View {
	let question: OralQuestion
	let onSelect: () -> Void

	var body: some View {
		Button(action: onSelect) {
			HStack(alignment: .top, spacing: SittingViewLayout.questionRowSpacing) {
				VStack(alignment: .leading, spacing: SittingViewLayout.questionTextSpacing) {
					Text(question.topic)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
						.fixedSize(horizontal: false, vertical: true)
					Text(question.speakerName)
						.font(.caption.weight(.medium))
						.foregroundStyle(.secondary)
					Text(questionMetadata)
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.fixedSize(horizontal: false, vertical: true)
					Text(question.firstLine)
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.top, SittingViewLayout.questionFirstLineTopPadding)
				}
				Spacer(minLength: SittingViewLayout.questionSpacerLength)
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.tertiary)
					.padding(.top, SittingViewLayout.questionChevronTopPadding)
			}
			.padding(.vertical, SittingViewLayout.questionVerticalPadding)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(accessibilityLabel)
		.accessibilityHint(NSLocalizedString("sitting.oralQuestions.openHint", comment: ""))
	}

	private var accessibilityLabel: String {
		[
			question.topic,
			question.speakerName,
			question.party.fullName,
			question.riding,
			question.firstLine
		]
		.filter { !$0.isEmpty }
		.joined(separator: ", ")
	}

	private var questionMetadata: String {
		[
			question.party.shortName,
			question.riding
		]
		.filter { !$0.isEmpty }
		.joined(separator: " · ")
	}
}

struct SittingSpeakerView: View {

	let name: String

	let party: Party

	init(member: ParliamentMember) {

		self.name = member.name

		self.party = member.party

	}

	init(name: String, party: Party) {

		self.name = name

		self.party = party

	}

	var body: some View {

		HStack(spacing: SittingViewLayout.speakerRowSpacing) {

			Text(verbatim: name)

				.font(.system(.footnote, design: .rounded).weight(.medium))

				.foregroundColor(.secondary)

			if let image = party.image {

				Image(uiImage: image)

					.resizable()

					.scaledToFit()

					.frame(width: SittingViewLayout.speakerIconSize, height: SittingViewLayout.speakerIconSize)

					.padding(SittingViewLayout.speakerIconPadding)

					.background(Circle().fill(Color.white).shadow(radius: 1))

			}

		}

	}

}
