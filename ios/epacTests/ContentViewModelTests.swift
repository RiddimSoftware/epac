@testable import epac
import Foundation
import Testing

@MainActor
struct ContentViewModelTests {
	@Test func selectedDateChangeCreatesImmediateSittingDestination() throws {
		let viewModel = ContentViewModel()
		let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 13)))
		let components = Calendar.current.dateComponents([.year, .month, .day], from: date)

		viewModel.nonSittingDate = date
		viewModel.selectedDate = components

		viewModel.onSelectedDateChanged(to: components)

		#expect(viewModel.selectedSittingDate == date)
		#expect(viewModel.selectedDate == nil)
		#expect(viewModel.selectedHansard == nil)
		#expect(viewModel.selectedSubject == nil)
		#expect(viewModel.nonSittingDate == nil)
	}
}
