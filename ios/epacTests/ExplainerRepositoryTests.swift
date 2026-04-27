import Testing
import Foundation
@testable import epac

// ExplainerRepository loads from a JSON string (via the internal init) so
// these tests run entirely in-process without touching the app bundle.
struct ExplainerRepositoryTests {

    private static let sampleJSON = """
    [
      {
        "term": "First Reading",
        "definition": "The formal introduction of a bill to Parliament.",
        "sourceLabel": "Parliament of Canada Glossary",
        "learnMoreURL": "https://www.parl.ca/About/Parliament/Education/FactSheets/pages/bills-e.aspx"
      },
      {
        "term": "Royal Assent",
        "definition": "The formal approval of a bill by the Governor General.",
        "sourceLabel": "Parliament of Canada",
        "learnMoreURL": "https://www.parl.ca/About/Parliament/Education/FactSheets/pages/bills-e.aspx"
      },
      {
        "term": "Private Member's Bill",
        "definition": "A bill introduced by any MP who is not a Cabinet minister.",
        "sourceLabel": "Parliament of Canada Glossary",
        "learnMoreURL": "https://www.parl.ca/About/Parliament/Education/FactSheets/pages/bills-e.aspx"
      }
    ]
    """

    // MARK: - Lookup

    @Test func exactMatchReturnsExplainer() {
        let repo = ExplainerRepository(json: Self.sampleJSON)
        let result = repo.explainer(for: "First Reading")
        #expect(result != nil)
        #expect(result?.term == "First Reading")
    }

    @Test func lookupIsCaseInsensitive() {
        let repo = ExplainerRepository(json: Self.sampleJSON)
        #expect(repo.explainer(for: "first reading") != nil)
        #expect(repo.explainer(for: "FIRST READING") != nil)
        #expect(repo.explainer(for: "First READING") != nil)
    }

    @Test func unknownTermReturnsNil() {
        let repo = ExplainerRepository(json: Self.sampleJSON)
        #expect(repo.explainer(for: "Consideration of Business") == nil)
        #expect(repo.explainer(for: "") == nil)
    }

    @Test func apostropheTermLookup() {
        // "Private Member's Bill" contains an apostrophe — verify it indexes correctly.
        let repo = ExplainerRepository(json: Self.sampleJSON)
        #expect(repo.explainer(for: "Private Member's Bill") != nil)
    }

    @Test func definitionAndSourceArePreserved() {
        let repo = ExplainerRepository(json: Self.sampleJSON)
        let result = repo.explainer(for: "Royal Assent")
        #expect(result?.definition == "The formal approval of a bill by the Governor General.")
        #expect(result?.sourceLabel == "Parliament of Canada")
    }

    @Test func learnMoreURLIsParsed() throws {
        let repo = ExplainerRepository(json: Self.sampleJSON)
        let result = try #require(repo.explainer(for: "Royal Assent"))
        #expect(result.learnMoreURL.host == "www.parl.ca")
    }

    // MARK: - Malformed input

    @Test func malformedJSONProducesEmptyIndex() {
        let repo = ExplainerRepository(json: "not json {{{")
        #expect(repo.explainer(for: "First Reading") == nil)
    }

    @Test func emptyArrayProducesEmptyIndex() {
        let repo = ExplainerRepository(json: "[]")
        #expect(repo.explainer(for: "First Reading") == nil)
    }
}
