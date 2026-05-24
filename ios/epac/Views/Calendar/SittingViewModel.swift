//
//  SittingViewModel.swift
//  epac
//

import Observation

struct OralQuestionSummary {
	let totalQuestions: Int
	let groups: [OralQuestionGroup]
}

struct OralQuestionGroup: Identifiable {
	let party: Party
	let partyAbbreviation: String
	let questions: [OralQuestion]

	var id: String { partyAbbreviation }
}

struct OralQuestion: Identifiable {
	let subject: SubjectOfBusiness
	let speech: Speech
	let firstMessage: SpeechMessage
	let topic: String
	let speakerName: String
	let party: Party
	let partyAbbreviation: String
	let riding: String
	let firstLine: String

	var id: String { firstMessage.hansardID }
}

@Observable
@MainActor
class SittingViewModel {
	var searchText: String = ""

	private enum Layout {
		static let firstLineCharacterLimit = 220
	}

	/// Subjects in `order` that have speeches and match the current search query.
	/// Preserves the existing hansardID sort. When searchText is empty, all
	/// non-empty subjects are returned (unchanged behaviour from before search).
	func filteredSubjects(for order: OrderOfBusiness) -> [SubjectOfBusiness] {
		let sorted = order.subjects
			.filter { !$0.speeches.isEmpty }
			.sorted(by: { $0.hansardID < $1.hansardID })
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return sorted }
		return sorted.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
	}

	/// Returns orders paired with their filtered subjects in a single pass,
	/// eliminating the double call to filteredSubjects that visibleOrders + ForEach
	/// would otherwise cause.
	func visibleOrderSubjects(from hansard: Hansard) -> [(order: OrderOfBusiness, subjects: [SubjectOfBusiness])] {
		hansard.orders
			.filter { !$0.subjects.isEmpty }
			.sorted(by: { $0.hansardID < $1.hansardID })
			.compactMap { order -> (OrderOfBusiness, [SubjectOfBusiness])? in
				let subjects = filteredSubjects(for: order)
				return subjects.isEmpty ? nil : (order, subjects)
			}
	}

	func oralQuestionsSummary(from hansard: Hansard) -> OralQuestionSummary? {
		guard let order = hansard.orders.first(where: { isOralQuestions(catchline: $0.catchline) }) else {
			return nil
		}

		let questions = order.subjects
			.sorted(by: { $0.hansardID < $1.hansardID })
			.compactMap(oralQuestion(from:))

		guard !questions.isEmpty else { return nil }

		let orderedParties = questions.reduce(into: [String]()) { result, question in
			if !result.contains(question.partyAbbreviation) {
				result.append(question.partyAbbreviation)
			}
		}

		let groups = orderedParties.map { abbreviation in
			let partyQuestions = questions.filter { $0.partyAbbreviation == abbreviation }
			return OralQuestionGroup(
				party: partyQuestions.first?.party ?? .independent,
				partyAbbreviation: abbreviation,
				questions: partyQuestions
			)
		}

		return OralQuestionSummary(totalQuestions: questions.count, groups: groups)
	}

	func prepareNavigation(to question: OralQuestion) {
		question.subject.currentSpeech = question.speech
		question.subject.currentSpeechID = question.speech.hansardID
		question.speech.currentMessage = question.firstMessage
		question.speech.currentMessageID = question.firstMessage.hansardID
	}

	private func isOralQuestions(catchline: String) -> Bool {
		let normalized = catchline
			.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		return normalized == "oral questions" ||
			normalized == "oral question period" ||
			normalized == "questions orales"
	}

	private func oralQuestion(from subject: SubjectOfBusiness) -> OralQuestion? {
		guard let speech = subject.speeches
			.sorted(by: { $0.hansardID < $1.hansardID })
			.first(where: { !$0.messages.isEmpty }),
			let firstMessage = speech.messages
			.sorted(by: { $0.hansardID < $1.hansardID })
			.first
		else {
			return nil
		}

		let party = Party.partyWithAbbreviation(firstMessage.partyAbbreviation)
		let speakerName = [firstMessage.firstName, firstMessage.lastName]
			.filter { !$0.isEmpty }
			.joined(separator: " ")

		return OralQuestion(
			subject: subject,
			speech: speech,
			firstMessage: firstMessage,
			topic: subject.title,
			speakerName: speakerName,
			party: party,
			partyAbbreviation: firstMessage.partyAbbreviation.isEmpty ? party.localizedAbbreviation : firstMessage.partyAbbreviation,
			riding: firstMessage.ridingName,
			firstLine: firstLine(of: firstMessage.content)
		)
	}

	private func firstLine(of content: String) -> String {
		let normalized = content
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return String(normalized.prefix(Layout.firstLineCharacterLimit))
	}
}
