@testable import epac
import Testing

struct SnippetParserTests {
    @Test func removesMarkTagsFromRenderedText() {
        let result = SnippetParser.parse("This is a <mark>test</mark> string")

        #expect(String(result.characters) == "This is a test string")
    }

    @Test func marksHighlightedTextAsEmphasized() {
        let result = SnippetParser.parse("This is a <mark>test</mark> string")

        let highlightedRun = result.runs.first { run in
            String(result[run.range].characters) == "test"
        }

        #expect(highlightedRun?.inlinePresentationIntent == .emphasized)
    }
}
