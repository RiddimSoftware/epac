import SwiftUI

@Observable
@MainActor
final class MemberSpeechFeedViewModel {
    let memberId: Int

    private(set) var speeches: [MemberSpeechEntry] = []
    private(set) var stats: MemberStats?
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?

    // Filter state
    var selectedTopic: String? = nil  // nil = "All"
    private(set) var topicChips: [SpeechTopicChip] = []

    private var currentPage = 0
    private var hasMore = true
    private let perPage = 20

    init(memberId: Int) {
        self.memberId = memberId
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        speeches = []
        currentPage = 0
        hasMore = true
        topicChips = []
        await loadNextPage()
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: MemberSpeechEntry) async {
        guard !isLoadingMore, hasMore else { return }
        let threshold = speeches.index(speeches.endIndex, offsetBy: -4, limitedBy: speeches.startIndex) ?? speeches.startIndex
        guard let index = speeches.firstIndex(where: { $0.id == currentItem.id }),
              index >= threshold else { return }
        isLoadingMore = true
        await loadNextPage()
        isLoadingMore = false
    }

    func applyTopicFilter(_ topic: String?) async {
        selectedTopic = topic
        speeches = []
        currentPage = 0
        hasMore = true
        isLoading = true
        await loadNextPage()
        isLoading = false
    }

    // MARK: - Private

    private func loadNextPage() async {
        guard hasMore else { return }
        let nextPage = currentPage + 1
        do {
            let page = try await MemberSpeechService.fetchPage(
                memberId: memberId,
                page: nextPage,
                perPage: perPage,
                topic: selectedTopic
            )
            speeches.append(contentsOf: page.speeches)
            currentPage = page.page
            totalCount = page.total
            hasMore = page.page < page.pages
            if stats == nil {
                stats = page.stats
            }
            updateTopicChips()
        } catch {
            self.error = "Could not load speeches. Please try again."
        }
    }

    private func updateTopicChips() {
        var counts: [String: Int] = [:]
        for entry in speeches {
            if let title = entry.subjectTitle, !title.isEmpty {
                counts[title, default: 0] += 1
            }
        }
        // Keep top 8 topics sorted by frequency
        topicChips = counts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { SpeechTopicChip(id: $0.key, count: $0.value) }
    }
}
