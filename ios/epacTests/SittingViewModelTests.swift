import Testing
import SwiftData
import Foundation
@testable import epac

@MainActor
struct SittingViewModelTests {

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV3.models), configurations: config)
	}

	private func subject(title: String, hansardID: String, withSpeeches: Bool = true, context: ModelContext) -> SubjectOfBusiness {
		let s = SubjectOfBusiness(title: title, hansardID: hansardID)
		if withSpeeches {
			let msg = SpeechMessage(
				firstName: "Test", lastName: "MP", partyAbbreviation: "Lib",
				ridingName: "Test", hansardID: "\(hansardID)-msg", content: ".",
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
}
