//
//  SittingView.swift
//  epac
//
//  Created by Sunny on 2024-12-13.
//

import SwiftData
import SwiftUI

struct SittingView: View {

	@Environment(\.modelContext) var modelContext

	@EnvironmentObject var fetch: Fetch

	let hansard: Hansard

	@Binding var selectedSubject: SubjectOfBusiness?

	@Query var members: [ParliamentMember]

	@State private var coordinator = MemberDownloadCoordinator()
	@State private var viewModel = SittingViewModel()

	var body: some View {
		let pairs = viewModel.visibleOrderSubjects(from: hansard)
		let oralQuestions = viewModel.oralQuestionsSummary(from: hansard)
		Group {
			if pairs.isEmpty && !viewModel.searchText.isEmpty {
				ContentUnavailableView.search(text: viewModel.searchText)
			} else {
				List {
					if let oralQuestions {
						OralQuestionsCard(summary: oralQuestions) { question in
							viewModel.prepareNavigation(to: question)
							selectedSubject = question.subject
						}
						.listRowSeparator(.hidden)
						.listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
					}
					ForEach(pairs, id: \.order.hansardID) { (order, subjects) in
						Section {
							ForEach(subjects) { subject in
								VStack(alignment: .leading, spacing: 8) {
									Text(subject.title)
										.font(.headline)
										.foregroundColor(.primary)

									HStack {
										Spacer()
										VStack(alignment: .trailing, spacing: 4) {
											ForEach(coordinator.speakers(for: subject, from: members, fetch: fetch)) { member in
												SittingSpeakerView(member: member)
											}
										}
									}
								}
								.padding(.vertical, 4)
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
								.padding(.top, 20)
								.padding(.bottom, 8)
						}
					}
				}
				.listStyle(.plain)
			}
		}
		.searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search debates")
	}
}

private struct OralQuestionsCard: View {
	let summary: OralQuestionSummary
	let onSelect: (OralQuestion) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			header
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 14) {
					ForEach(summary.groups) { group in
						partyGroup(group)
					}
				}
				.padding(.vertical, 2)
			}
		}
		.padding(16)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color(uiColor: .secondarySystemGroupedBackground))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 8)
				.stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
		)
		.accessibilityElement(children: .contain)
	}

	private var header: some View {
		HStack(alignment: .firstTextBaseline) {
			VStack(alignment: .leading, spacing: 4) {
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
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				if let image = group.party.image {
					Image(uiImage: image)
						.resizable()
						.scaledToFit()
						.frame(width: 18, height: 18)
						.padding(2)
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
			HStack(alignment: .top, spacing: 10) {
				VStack(alignment: .leading, spacing: 5) {
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
						.padding(.top, 2)
				}
				Spacer(minLength: 8)
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.tertiary)
					.padding(.top, 4)
			}
			.padding(.vertical, 8)
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

		HStack(spacing: 6) {

			Text(verbatim: name)

				.font(.system(.footnote, design: .rounded).weight(.medium))

				.foregroundColor(.secondary)

			if let image = party.image {

				Image(uiImage: image)

					.resizable()

					.scaledToFit()

					.frame(width: 16, height: 16)

					.padding(2)

					.background(Circle().fill(Color.white).shadow(radius: 1))

			}

		}

	}

}
