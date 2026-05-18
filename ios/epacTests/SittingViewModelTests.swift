@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
struct SittingViewModelTests {

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
	}

	private func subject(
		title: String,
		hansardID: String,
		withSpeeches: Bool = true,
		firstName: String = "Test",
		lastName: String = "MP",
		partyAbbreviation: String = "Lib",
		ridingName: String = "Test",
		content: String = ".",
		context: ModelContext
	) -> SubjectOfBusiness {
		let s = SubjectOfBusiness(title: title, hansardID: hansardID)
		if withSpeeches {
			let msg = SpeechMessage(
				firstName: firstName, lastName: lastName, partyAbbreviation: partyAbbreviation,
				ridingName: ridingName, hansardID: "\(hansardID)-msg", content: content,
				timestamp: Date()
			)
			let speech = Speech(messages: [msg], hansardID: "\(hansardID)-speech", date: Date(), title: title)
			s.speeches = [speech]
		}
		context.insert(s)
		return s
	}

	private func order(catchline: String, subjects: [SubjectOfBusiness], context: ModelContext) -> OrderOfBusiness {
		let o = OrderOfBusiness(hansardID: "order-\(catchline)", catchline: catchline, subjects: subjects)
		context.insert(o)
		return o
	}

	// MARK: - filteredSubjects — no search text

	@Test func emptySearchReturnsAllSubjectsWithSpeeches() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "Carbon Tax", hansardID: "s1", context: ctx),
			subject(title: "Housing Crisis", hansardID: "s2", context: ctx),
			subject(title: "Empty", hansardID: "s3", withSpeeches: false, context: ctx)
		]
		let o = order(catchline: "Oral Questions", subjects: subjects, context: ctx)
		let vm = SittingViewModel()

		let result = vm.filteredSubjects(for: o)
		#expect(result.count == 2)
		#expect(!result.contains(where: { $0.title == "Empty" }))
	}

	@Test func subjectsAreSortedByHansardID() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "C", hansardID: "s3", context: ctx),
			subject(title: "A", hansardID: "s1", context: ctx),
			subject(title: "B", hansardID: "s2", context: ctx)
		]
		let o = order(catchline: "Routine", subjects: subjects, context: ctx)
		let vm = SittingViewModel()

		let result = vm.filteredSubjects(for: o)
		#expect(result.map { $0.title } == ["A", "B", "C"])
	}

	// MARK: - filteredSubjects — with search text

	@Test func searchMatchesSubjectTitle() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "Carbon Tax Discussion", hansardID: "s1", context: ctx),
			subject(title: "Housing Affordability", hansardID: "s2", context: ctx),
			subject(title: "Carbon Capture Investment", hansardID: "s3", context: ctx)
		]
		let o = order(catchline: "Oral Questions", subjects: subjects, context: ctx)
		let vm = SittingViewModel()
		vm.searchText = "carbon"

		let result = vm.filteredSubjects(for: o)
		#expect(result.count == 2)
		#expect(result.allSatisfy { $0.title.lowercased().contains("carbon") })
	}

	@Test func searchIsCaseInsensitive() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "CARBON TAX", hansardID: "s1", context: ctx),
			subject(title: "Housing", hansardID: "s2", context: ctx)
		]
		let o = order(catchline: "Routine", subjects: subjects, context: ctx)
		let vm = SittingViewModel()
		vm.searchText = "carbon"

		#expect(vm.filteredSubjects(for: o).count == 1)
	}

	@Test func searchWithNoMatchReturnsEmpty() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "Carbon Tax", hansardID: "s1", context: ctx),
			subject(title: "Housing", hansardID: "s2", context: ctx)
		]
		let o = order(catchline: "Routine", subjects: subjects, context: ctx)
		let vm = SittingViewModel()
		vm.searchText = "xyz123nomatch"

		#expect(vm.filteredSubjects(for: o).isEmpty)
	}

	@Test func searchTrimsWhitespace() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "Carbon Tax", hansardID: "s1", context: ctx)
		]
		let o = order(catchline: "Routine", subjects: subjects, context: ctx)
		let vm = SittingViewModel()
		vm.searchText = "  carbon  "

		#expect(vm.filteredSubjects(for: o).count == 1)
	}

	@Test func clearingSearchRestoresAllResults() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "Carbon Tax", hansardID: "s1", context: ctx),
			subject(title: "Housing", hansardID: "s2", context: ctx)
		]
		let o = order(catchline: "Routine", subjects: subjects, context: ctx)
		let vm = SittingViewModel()

		vm.searchText = "carbon"
		#expect(vm.filteredSubjects(for: o).count == 1)
		vm.searchText = ""
		#expect(vm.filteredSubjects(for: o).count == 2)
	}

	@Test func whitespaceOnlySearchBehavesAsEmpty() throws {
		let ctx = ModelContext(try makeContainer())
		let subjects = [
			subject(title: "Carbon Tax", hansardID: "s1", context: ctx),
			subject(title: "Housing", hansardID: "s2", context: ctx)
		]
		let o = order(catchline: "Routine", subjects: subjects, context: ctx)
		let vm = SittingViewModel()
		vm.searchText = "   "

		// Whitespace-only is trimmed to empty, so all subjects with speeches are returned.
		#expect(vm.filteredSubjects(for: o).count == 2)
	}

	// MARK: - visibleOrderSubjects

	@Test func visibleOrderSubjectsExcludesOrdersWithNoMatchingSubjects() throws {
		let ctx = ModelContext(try makeContainer())
		let carbonSubject = subject(title: "Carbon Tax", hansardID: "s1", context: ctx)
		let housingSubject = subject(title: "Housing Affordability", hansardID: "s2", context: ctx)
		let orderA = order(catchline: "Oral Questions", subjects: [carbonSubject], context: ctx)
		let orderB = order(catchline: "Routine Proceedings", subjects: [housingSubject], context: ctx)

		let hansard = Hansard(date: Date(), hansardID: "h1", parliamentNumber: 45, sessionNumber: 1, orders: [orderA, orderB])
		ctx.insert(hansard)

		let vm = SittingViewModel()
		vm.searchText = "carbon"

		let pairs = vm.visibleOrderSubjects(from: hansard)
		#expect(pairs.count == 1)
		#expect(pairs[0].order.catchline == "Oral Questions")
		#expect(pairs[0].subjects.count == 1)
		#expect(pairs[0].subjects[0].title == "Carbon Tax")
	}

	@Test func visibleOrderSubjectsReturnsAllWhenSearchEmpty() throws {
		let ctx = ModelContext(try makeContainer())
		let s1 = subject(title: "Carbon Tax", hansardID: "s1", context: ctx)
		let s2 = subject(title: "Housing", hansardID: "s2", context: ctx)
		let o = order(catchline: "Oral Questions", subjects: [s1, s2], context: ctx)
		let hansard = Hansard(date: Date(), hansardID: "h2", parliamentNumber: 45, sessionNumber: 1, orders: [o])
		ctx.insert(hansard)

		let vm = SittingViewModel()

		let pairs = vm.visibleOrderSubjects(from: hansard)
		#expect(pairs.count == 1)
		#expect(pairs[0].subjects.count == 2)
	}

	// MARK: - oralQuestionsSummary

	@Test func oralQuestionsSummaryFindsEnglishCatchline() throws {
		let ctx = ModelContext(try makeContainer())
		let economy = subject(
			title: "The Economy",
			hansardID: "s1",
			firstName: "Alex",
			lastName: "MP",
			partyAbbreviation: "CPC",
			ridingName: "Calgary Centre",
			content: "Mr. Speaker, will the minister answer the question?\nSecond line.",
			context: ctx
		)
		let order = order(catchline: "ORAL QUESTIONS", subjects: [economy], context: ctx)
		let hansard = Hansard(date: Date(), hansardID: "h3", parliamentNumber: 45, sessionNumber: 1, orders: [order])
		ctx.insert(hansard)

		let summary = SittingViewModel().oralQuestionsSummary(from: hansard)

		#expect(summary?.totalQuestions == 1)
		#expect(summary?.groups.first?.party == .conservative)
		#expect(summary?.groups.first?.questions.first?.topic == "The Economy")
		#expect(summary?.groups.first?.questions.first?.speakerName == "Alex MP")
		#expect(summary?.groups.first?.questions.first?.riding == "Calgary Centre")
		#expect(summary?.groups.first?.questions.first?.firstLine == "Mr. Speaker, will the minister answer the question? Second line.")
	}

	@Test func oralQuestionsSummaryFindsFrenchCatchline() throws {
		let ctx = ModelContext(try makeContainer())
		let justice = subject(title: "Justice", hansardID: "s1", partyAbbreviation: "BQ", context: ctx)
		let order = order(catchline: "QUESTIONS ORALES", subjects: [justice], context: ctx)
		let hansard = Hansard(date: Date(), hansardID: "h4", parliamentNumber: 45, sessionNumber: 1, orders: [order])
		ctx.insert(hansard)

		let summary = SittingViewModel().oralQuestionsSummary(from: hansard)

		#expect(summary?.totalQuestions == 1)
		#expect(summary?.groups.first?.party == .bloc)
	}

	@Test func oralQuestionsSummaryIgnoresOtherOrders() throws {
		let ctx = ModelContext(try makeContainer())
		let subject = subject(title: "Government Orders", hansardID: "s1", context: ctx)
		let order = order(catchline: "Government Orders", subjects: [subject], context: ctx)
		let hansard = Hansard(date: Date(), hansardID: "h5", parliamentNumber: 45, sessionNumber: 1, orders: [order])
		ctx.insert(hansard)

		#expect(SittingViewModel().oralQuestionsSummary(from: hansard) == nil)
	}

	@Test func oralQuestionsSummaryGroupsQuestionsByFirstSpeakerParty() throws {
		let ctx = ModelContext(try makeContainer())
		let liberal = subject(title: "Housing", hansardID: "s2", partyAbbreviation: "Lib", context: ctx)
		let conservative = subject(title: "Taxation", hansardID: "s1", partyAbbreviation: "CPC", context: ctx)
		let order = order(catchline: "Oral Questions", subjects: [liberal, conservative], context: ctx)
		let hansard = Hansard(date: Date(), hansardID: "h6", parliamentNumber: 45, sessionNumber: 1, orders: [order])
		ctx.insert(hansard)

		let summary = SittingViewModel().oralQuestionsSummary(from: hansard)

		#expect(summary?.groups.map { $0.partyAbbreviation } == ["CPC", "Lib"])
		#expect(summary?.groups.first?.questions.map { $0.topic } == ["Taxation"])
		#expect(summary?.groups.last?.questions.map { $0.topic } == ["Housing"])
	}

	@Test func prepareNavigationStoresSpeechAndFirstMessageForResume() throws {
		let ctx = ModelContext(try makeContainer())
		let topic = subject(title: "The Economy", hansardID: "s1", context: ctx)
		let order = order(catchline: "Oral Questions", subjects: [topic], context: ctx)
		let hansard = Hansard(date: Date(), hansardID: "h7", parliamentNumber: 45, sessionNumber: 1, orders: [order])
		ctx.insert(hansard)

		let vm = SittingViewModel()
		let question = try #require(vm.oralQuestionsSummary(from: hansard)?.groups.first?.questions.first)
		vm.prepareNavigation(to: question)

		#expect(topic.currentSpeechID == question.speech.hansardID)
		#expect(topic.currentSpeech?.hansardID == question.speech.hansardID)
		#expect(question.speech.currentMessageID == question.firstMessage.hansardID)
		#expect(question.speech.currentMessage?.hansardID == question.firstMessage.hansardID)
	}

	@Test func upcomingSittingDatesReturnsLoadedDatesInsideNextThirtyDays() {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Toronto")!
		let start = date(year: 2026, month: 4, day: 28, calendar: calendar)
		let vm = SittingCalendarViewModel()
		vm.dates = [
			components(year: 2026, month: 4, day: 27),
			components(year: 2026, month: 4, day: 29)
		]
		vm.futureDates = [
			components(year: 2026, month: 5, day: 12),
			components(year: 2026, month: 6, day: 1)
		]

		let result = vm.upcomingSittingDates(from: start, throughDays: 30, calendar: calendar)
		let days = result.map { calendar.component(.day, from: $0) }

		#expect(days == [29, 12])
	}

	@Test func calendarExportSubscriptionURLUsesArtifactBase() {
		let baseURL = URL(string: "https://assets.example.test")!
		let url = CalendarExportService.subscriptionURL(baseURL: baseURL)

		#expect(url.absoluteString == "https://assets.example.test/calendar/v1/house.ics")
	}

	private func components(year: Int, month: Int, day: Int) -> DateComponents {
		DateComponents(year: year, month: month, day: day)
	}

	private func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
		calendar.date(from: components(year: year, month: month, day: day))!
	}
}
