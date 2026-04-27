import Testing
import Foundation
@testable import epac

// MemberSpeechFeedViewModel.buildTopicCounts is a pure function — no network,
// no SwiftData, no async. Tests exercise the sorting and deduplication logic
// directly without standing up a model container.
@MainActor
struct MemberSpeechFeedViewModelTests {

    private func entry(id: String, topic: String?) -> MemberSpeechEntry {
        MemberSpeechEntry(
            id: id,
            sittingDate: "2024-11-12",
            parliamentNum: 45,
            sessionNum: 1,
            subjectTitle: topic,
            preview: "preview",
            wordCount: 100,
            filename: "hansard.xml"
        )
    }

    // MARK: - buildTopicCounts

    @Test func emptySpeeches_returnsEmptyTopics() {
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: [])
        #expect(result.isEmpty)
    }

    @Test func nilTopics_areExcluded() {
        let speeches = [entry(id: "1", topic: nil), entry(id: "2", topic: nil)]
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: speeches)
        #expect(result.isEmpty)
    }

    @Test func emptyStringTopics_areExcluded() {
        let speeches = [entry(id: "1", topic: ""), entry(id: "2", topic: "")]
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: speeches)
        #expect(result.isEmpty)
    }

    @Test func singleTopic_countIsOne() {
        let speeches = [entry(id: "1", topic: "Environment")]
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: speeches)
        #expect(result.count == 1)
        #expect(result[0].topic == "Environment")
        #expect(result[0].count == 1)
    }

    @Test func duplicateTopics_areAggregated() {
        let speeches = [
            entry(id: "1", topic: "Economy"),
            entry(id: "2", topic: "Economy"),
            entry(id: "3", topic: "Economy"),
        ]
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: speeches)
        #expect(result.count == 1)
        #expect(result[0].count == 3)
    }

    @Test func multipleTopics_sortedByDescendingCount() {
        let speeches = [
            entry(id: "1", topic: "Health"),
            entry(id: "2", topic: "Economy"),
            entry(id: "3", topic: "Economy"),
            entry(id: "4", topic: "Environment"),
            entry(id: "5", topic: "Environment"),
            entry(id: "6", topic: "Environment"),
        ]
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: speeches)
        #expect(result.count == 3)
        #expect(result[0].topic == "Environment")
        #expect(result[0].count == 3)
        #expect(result[1].topic == "Economy")
        #expect(result[1].count == 2)
        #expect(result[2].topic == "Health")
        #expect(result[2].count == 1)
    }

    @Test func mixedNilAndValidTopics_onlyValidCounted() {
        let speeches = [
            entry(id: "1", topic: "Defence"),
            entry(id: "2", topic: nil),
            entry(id: "3", topic: ""),
            entry(id: "4", topic: "Defence"),
        ]
        let result = MemberSpeechFeedViewModel.buildTopicCounts(from: speeches)
        #expect(result.count == 1)
        #expect(result[0].topic == "Defence")
        #expect(result[0].count == 2)
    }

    // MARK: - initial ViewModel state

    @Test func initialState_isIdle() {
        let vm = MemberSpeechFeedViewModel(memberId: 99)
        #expect(vm.speeches.isEmpty)
        #expect(vm.stats == nil)
        #expect(!vm.isLoading)
        #expect(vm.hasMore)
        #expect(vm.errorMessage == nil)
        #expect(vm.selectedTopic == nil)
        #expect(vm.topicCounts.isEmpty)
    }

    @Test func memberId_zero_guardsPreventsLoad() async {
        let vm = MemberSpeechFeedViewModel(memberId: 0)
        await vm.loadNextPage()
        // memberId == 0 short-circuits; isLoading never flips
        #expect(!vm.isLoading)
        #expect(vm.speeches.isEmpty)
    }
}
