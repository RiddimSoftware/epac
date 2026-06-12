@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
struct SearchViewModelTests {
    @Test func configureRefreshesExistingDebateQuery() {
        let viewModel = SearchViewModel()

        viewModel.updateResults(members: [], votes: [], bills: [], query: "housing")
        #expect(viewModel.searchResults.debates.isEmpty)

        viewModel.configure(searchHansard: StubSearchHansardUseCase(matches: [
            SearchHansard.Match(
                subjectID: "subject-1",
                subjectTitle: "Housing affordability",
                hansardDate: Date(timeIntervalSince1970: 1_000)
            )
        ]))

        #expect(viewModel.searchResults.debates.map(\.subjectID) == ["subject-1"])
    }

    @Test func updatingInputsRefreshesExistingBillQuery() {
        let viewModel = SearchViewModel()

        viewModel.updateResults(members: [], votes: [], bills: [], query: "C-42")
        #expect(viewModel.searchResults.bills.isEmpty)

        viewModel.updateSearchInputs(
            members: [],
            votes: [],
            bills: [
                Bill(
                    id: "C-42",
                    number: "C-42",
                    title: "An Act respecting search regressions",
                    sponsorName: "Jane Doe",
                    status: .inProgress,
                    currentStage: "First Reading",
                    introducedDate: nil,
                    stages: [],
                    legisInfoURL: URL(string: "https://example.com/bills/C-42")!,
                    billType: .privateMember,
                    parliament: 44,
                    session: 1
                )
            ]
        )

        #expect(viewModel.searchResults.bills.map(\.bill.number) == ["C-42"])
    }

    @Test func resolveDebateReturnsMatchingModels() throws {
        let container = try ModelContainer(
            for: Hansard.self, SubjectOfBusiness.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let targetDate = Date(timeIntervalSince1970: 1000)
        let targetSubjectID = "sub-1"

        // Setup data
        let hansard = Hansard(date: targetDate, hansardID: "h1", parliamentNumber: 44, sessionNumber: 1)
        let subject = SubjectOfBusiness(title: "Test Title", hansardID: targetSubjectID)

        context.insert(hansard)
        context.insert(subject)

        // Add some noise
        context.insert(Hansard(date: Date(timeIntervalSince1970: 2000), hansardID: "h2", parliamentNumber: 44, sessionNumber: 1))
        context.insert(SubjectOfBusiness(title: "Noise Title", hansardID: "sub-2"))

        let viewModel = SearchViewModel()
        let result = SearchViewModel.DebateResult(
            id: "match-1",
            hansardDate: targetDate,
            subjectID: targetSubjectID,
            subjectTitle: "Test Title"
        )

        let (resolvedHansard, resolvedSubject) = viewModel.resolveDebate(result, modelContext: context)

        #expect(resolvedHansard?.hansardID == "h1")
        #expect(resolvedSubject?.hansardID == targetSubjectID)
    }
}

@MainActor
private struct StubSearchHansardUseCase: SearchHansardUseCase {
    let matches: [SearchHansard.Match]

    func execute(query: String) -> [SearchHansard.Match] {
        matches
    }
}
