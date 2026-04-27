import Testing
import SwiftData
import Foundation
@testable import epac

struct ExpendituresViewModelTests {

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV3.models), configurations: config)
	}

	private func expenditure(
		firstName: String, lastName: String,
		year: Int, quarter: Int,
		travel: Double = 0, hospitality: Double = 0, contracts: Double = 0,
		context: ModelContext
	) -> SummaryExpenditure {
		let e = SummaryExpenditure(
			firstName: firstName, lastName: lastName,
			constituency: "Test", caucus: "Lib",
			salaries: 0, travel: travel, hospitality: hospitality, contracts: contracts,
			year: year, quarter: quarter
		)
		context.insert(e)
		return e
	}

	// MARK: - periods

	@Test func periodsStartFrom2021Q2() {
		let vm = ExpendituresViewModel()
		let oldest = vm.periods.last
		#expect(oldest?.year == 2021)
		#expect(oldest?.quarter == 2)
	}

	@Test func periodsAreInReverseChronologicalOrder() {
		let vm = ExpendituresViewModel()
		for i in 0..<(vm.periods.count - 1) {
			let a = vm.periods[i]
			let b = vm.periods[i + 1]
			let aValue = a.year * 10 + a.quarter
			let bValue = b.year * 10 + b.quarter
			#expect(aValue >= bValue)
		}
	}

	@Test func periodsContainCurrentQuarter() {
		let vm = ExpendituresViewModel()
		let cal = Calendar.current
		let now = Date()
		let currentYear = cal.component(.year, from: now)
		let currentQuarter = (cal.component(.month, from: now) - 1) / 3 + 1
		#expect(vm.periods.contains(where: { $0.year == currentYear && $0.quarter == currentQuarter }))
	}

	@Test func periodIDIsHumanReadable() {
		let period = ExpendituresViewModel.ExpenditurePeriod(year: 2024, quarter: 3)
		#expect(period.id == "2024 Q3")
	}

	@Test func reportedFiscalYearAccountsForFiscalMonitorPublicationLag() throws {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_CA_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"

		#expect(ExpendituresViewModel.reportedFiscalYearStartYear(for: try #require(formatter.date(from: "2026-04-27"))) == 2025)
		#expect(ExpendituresViewModel.reportedFiscalYearStartYear(for: try #require(formatter.date(from: "2026-07-31"))) == 2026)
	}

	// MARK: - filteredExpenditures — year/quarter filter

	@Test func returnsOnlySelectedYearAndQuarter() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024
		vm.selectedQuarter = 1

		let expenditures = [
			expenditure(firstName: "Alice", lastName: "Smith", year: 2024, quarter: 1, travel: 1000, context: ctx),
			expenditure(firstName: "Bob", lastName: "Jones", year: 2023, quarter: 4, travel: 500, context: ctx),
			expenditure(firstName: "Carol", lastName: "Lee", year: 2024, quarter: 2, travel: 750, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result.count == 1)
		#expect(result.first?.firstName == "Alice")
	}

	// MARK: - filteredExpenditures — search

	@Test func searchFiltersByFirstName() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024
		vm.selectedQuarter = 1
		vm.searchText = "alice"

		let expenditures = [
			expenditure(firstName: "Alice", lastName: "Smith", year: 2024, quarter: 1, context: ctx),
			expenditure(firstName: "Bob", lastName: "Jones", year: 2024, quarter: 1, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result.count == 1)
		#expect(result.first?.firstName == "Alice")
	}

	@Test func searchFiltersByLastName() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024
		vm.selectedQuarter = 1
		vm.searchText = "jones"

		let expenditures = [
			expenditure(firstName: "Alice", lastName: "Smith", year: 2024, quarter: 1, context: ctx),
			expenditure(firstName: "Bob", lastName: "Jones", year: 2024, quarter: 1, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result.count == 1)
		#expect(result.first?.lastName == "Jones")
	}

	@Test func emptySearchReturnsAllForPeriod() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024
		vm.selectedQuarter = 1

		let expenditures = [
			expenditure(firstName: "Alice", lastName: "Smith", year: 2024, quarter: 1, travel: 100, context: ctx),
			expenditure(firstName: "Bob", lastName: "Jones", year: 2024, quarter: 1, travel: 200, context: ctx)
		]
		#expect(vm.filteredExpenditures(from: expenditures).count == 2)
	}

	// MARK: - filteredExpenditures — sort orders

	@Test func sortByTotalDescending() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024; vm.selectedQuarter = 1
		vm.sortOrder = .total

		let expenditures = [
			expenditure(firstName: "Low", lastName: "Spender", year: 2024, quarter: 1, travel: 100, context: ctx),
			expenditure(firstName: "High", lastName: "Spender", year: 2024, quarter: 1, travel: 1000, context: ctx),
			expenditure(firstName: "Mid", lastName: "Spender", year: 2024, quarter: 1, travel: 500, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result[0].firstName == "High")
		#expect(result[1].firstName == "Mid")
		#expect(result[2].firstName == "Low")
	}

	@Test func sortByNameAscending() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024; vm.selectedQuarter = 1
		vm.sortOrder = .name

		let expenditures = [
			expenditure(firstName: "Charlie", lastName: "Ziegler", year: 2024, quarter: 1, context: ctx),
			expenditure(firstName: "Alice", lastName: "Aardvark", year: 2024, quarter: 1, context: ctx),
			expenditure(firstName: "Bob", lastName: "Miller", year: 2024, quarter: 1, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result[0].lastName == "Aardvark")
		#expect(result[1].lastName == "Miller")
		#expect(result[2].lastName == "Ziegler")
	}

	@Test func sortByTravelDescending() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024; vm.selectedQuarter = 1
		vm.sortOrder = .travel

		let expenditures = [
			expenditure(firstName: "A", lastName: "A", year: 2024, quarter: 1, travel: 200, hospitality: 1000, context: ctx),
			expenditure(firstName: "B", lastName: "B", year: 2024, quarter: 1, travel: 800, hospitality: 10, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		// Sorted by travel, not total: B (800 travel) > A (200 travel)
		#expect(result[0].firstName == "B")
	}

	@Test func sortByHospitalityDescending() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024; vm.selectedQuarter = 1
		vm.sortOrder = .hospitality

		let expenditures = [
			expenditure(firstName: "A", lastName: "A", year: 2024, quarter: 1, travel: 1000, hospitality: 50, context: ctx),
			expenditure(firstName: "B", lastName: "B", year: 2024, quarter: 1, travel: 100, hospitality: 900, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result[0].firstName == "B")
	}

	@Test func sortByContractsDescending() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024; vm.selectedQuarter = 1
		vm.sortOrder = .contracts

		let expenditures = [
			expenditure(firstName: "A", lastName: "A", year: 2024, quarter: 1, contracts: 300, context: ctx),
			expenditure(firstName: "B", lastName: "B", year: 2024, quarter: 1, contracts: 700, context: ctx)
		]
		let result = vm.filteredExpenditures(from: expenditures)
		#expect(result[0].firstName == "B")
	}

	// MARK: - loadFailed

	@Test func loadFailedStartsFalse() {
		let vm = ExpendituresViewModel()
		#expect(vm.loadFailed == false)
	}

	/// When the selected period already has cached data, loadData returns early
	/// without a network call. loadFailed must be cleared (reset to false) at the
	/// top of loadData so that a stale error from a previous period does not bleed
	/// into the new one.
	@Test func loadFailedClearedWhenDataAlreadyExists() async throws {
		let container = try makeContainer()
		let ctx = ModelContext(container)
		let fetch = Fetch(modelContainer: container)

		let vm = ExpendituresViewModel()
		vm.selectedYear = 2024
		vm.selectedQuarter = 1
		// Simulate a stale error left over from a prior period.
		vm.loadFailed = true

		let cached = expenditure(firstName: "Alice", lastName: "Smith", year: 2024, quarter: 1, context: ctx)
		try ctx.save()

		await vm.loadData(expenditures: [cached], fetch: fetch)

		#expect(vm.loadFailed == false)
		#expect(vm.isLoading == false)
	}

	/// When no cached data exists, loadData sets isLoading=true then isLoading=false
	/// regardless of whether the fetch succeeds or fails. The selected period is
	/// intentionally outside the Commons disclosure range, so the fetch fails
	/// deterministically without relying on network availability.
	@Test func loadFailedSetOnNetworkError() async throws {
		let container = try makeContainer()
		let fetch = Fetch(modelContainer: container)

		let vm = ExpendituresViewModel()
		vm.selectedYear = 1900
		vm.selectedQuarter = 1

		// Pass an empty expenditures list so exists=false and a network call is made.
		await vm.loadData(expenditures: [], fetch: fetch)

		// After a failed network call the loading indicator must be off.
		#expect(vm.isLoading == false)
		// loadFailed must be true so the error state is shown.
		#expect(vm.loadFailed == true)
	}
}
