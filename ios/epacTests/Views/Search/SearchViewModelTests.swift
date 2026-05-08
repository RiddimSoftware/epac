@testable import epac
import SwiftData
import Testing
import Foundation

@MainActor
struct SearchViewModelTests {
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
