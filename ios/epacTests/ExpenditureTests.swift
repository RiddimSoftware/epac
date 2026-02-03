import Testing
import Foundation
@testable import epac

struct ExpenditureTests {
	
	@Test func parseSummaryExpenditures() async {
		let url = Bundle(for: ForThisOnly.self).url(forResource: "MembersExpenditures.2026Q2",
													withExtension: "csv")!
		let parser = CSVParser(file: url)
		let expenditures = SummaryExpenditure.fromCSV(parser, year: 2026, quarter: 2)
		let list = await expenditures.collect()
		
		#expect(list.count == 459)

		// "Block,  Kelly",Carlton Trail—Eagle Creek,Conservative,86859.81,20406.36,472.89,17820.61
		#expect(list.first?.firstName == "Kelly")
		#expect(list.first?.lastName == "Block")
		#expect(list.first?.constituency == "Carlton Trail—Eagle Creek")
		#expect(list.first?.caucus == "Conservative")
		#expect(list.first?.salaries == 86859.81)
		#expect(list.first?.travel == 20406.36)
		#expect(list.first?.hospitality == 472.89)
		#expect(list.first?.contracts == 17820.61)

		// "Zuberi,  Sameer",Pierrefonds—Dollard,Liberal,95852.47,16807.25,5739.29,28537.64
		#expect(list.last?.firstName == "Sameer")
		#expect(list.last?.lastName == "Zuberi")
		#expect(list.last?.constituency == "Pierrefonds—Dollard")
		#expect(list.last?.caucus == "Liberal")
		#expect(list.last?.salaries == 95852.47)
		#expect(list.last?.travel == 16807.25)
		#expect(list.last?.hospitality == 5739.29)
		#expect(list.last?.contracts == 28537.64)

		// "Carney,  Right Hon. Mark",Nepean,Liberal,0,0,0,17280.02
		#expect(list[1].firstName == "Mark")
		#expect(list[1].lastName == "Carney")
		#expect(list[1].constituency == "Nepean")
		#expect(list[1].caucus == "Liberal")
		#expect(list[1].salaries == 0)
		#expect(list[1].travel == 0)
		#expect(list[1].hospitality == 0)
		#expect(list[1].contracts == 17280.02)
	}
}

extension AsyncSequence {
    /// Collects all elements of an asynchronous sequence into an array.
    func collect() async rethrows -> [Element] {
        var elements: [Element] = []
        for try await element in self {
            elements.append(element)
        }
        return elements
    }
}