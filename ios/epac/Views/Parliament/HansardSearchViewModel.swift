import Foundation
import Observation

@Observable
final class HansardSearchViewModel {
    @MainActor var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    @MainActor private(set) var isLoading: Bool = false
    @MainActor private(set) var results: [HansardSearchResult] = []
    @MainActor private(set) var error: Error?
    @MainActor private(set) var page: Int = 1
    @MainActor private(set) var hasMore: Bool = false
    @MainActor private(set) var total: Int = 0

    @ObservationIgnored private let service: any HansardSearchProviding
    @ObservationIgnored private let debounceDuration: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var activeRequestTask: Task<HansardSearchResponse, Error>?
    @ObservationIgnored private var activeRequestID = UUID()
    @ObservationIgnored private var perPage = Constants.defaultPerPage
    @ObservationIgnored private var suppressQueryObserver = false

    private enum Constants {
        static let debounceMilliseconds = 300
        static let debounceDuration = Duration.milliseconds(debounceMilliseconds)
        static let firstPage = 1
        static let defaultPerPage = 20
    }

    private struct LoadMoreContext {
        let query: String
        let retainedResults: [HansardSearchResult]
        let currentPage: Int
        let currentTotal: Int
        let currentHasMore: Bool
        let nextPage: Int
    }

    @MainActor
    init(service: any HansardSearchProviding = BackendHansardSearchService()) {
        self.service = service
        debounceDuration = Constants.debounceDuration
    }

    @MainActor
    init(service: any HansardSearchProviding, debounceDuration: Duration) {
        self.service = service
        self.debounceDuration = debounceDuration
    }

    @MainActor
    func search() async {
        debounceTask?.cancel()
        debounceTask = nil
        await performSearch()
    }

    @MainActor
    private func performSearch() async {
        let trimmedQuery = normalizedQuery()
        guard !trimmedQuery.isEmpty else {
            resetSearchState()
            return
        }

        let requestID = beginRequest()
        isLoading = true
        error = nil
        page = Constants.firstPage
        total = 0
        hasMore = false
        results = []

        let task = makeRequestTask(query: trimmedQuery, page: Constants.firstPage, perPage: perPage)
        activeRequestTask = task

        do {
            let response = try await task.value
            guard shouldApplyResponse(for: requestID) else { return }
            applySearchResponse(response)
        } catch is CancellationError {
            return
        } catch {
            guard shouldApplyResponse(for: requestID) else { return }
            activeRequestTask = nil
            self.error = error
            isLoading = false
        }
    }

    @MainActor
    func loadMore() async {
        guard let context = makeLoadMoreContext() else { return }

        let requestID = beginRequest()

        isLoading = true
        error = nil

        let task = makeRequestTask(query: context.query, page: context.nextPage, perPage: perPage)
        activeRequestTask = task

        do {
            let response = try await task.value
            guard shouldApplyResponse(for: requestID) else { return }
            applyLoadMoreResponse(response)
        } catch is CancellationError {
            return
        } catch {
            guard shouldApplyResponse(for: requestID) else { return }
            activeRequestTask = nil
            results = context.retainedResults
            page = context.currentPage
            total = context.currentTotal
            hasMore = context.currentHasMore
            self.error = error
            isLoading = false
        }
    }

    @MainActor
    func clear() {
        debounceTask?.cancel()
        invalidateActiveRequest()
        suppressQueryObserver = true
        query = ""
        suppressQueryObserver = false
        resetSearchState()
    }

    @MainActor
    private func scheduleSearch() {
        guard !suppressQueryObserver else { return }

        debounceTask?.cancel()
        invalidateActiveRequest()

        guard !normalizedQuery().isEmpty else {
            resetSearchState()
            return
        }

        let debounceDuration = debounceDuration
        // Task.sleep-based debounce: each keystroke cancels the pending task
        // so only the latest query is allowed to trigger search().
        debounceTask = Task { @MainActor [weak self, debounceDuration] in
            do {
                try await Task.sleep(for: debounceDuration)
                guard let self, !Task.isCancelled else { return }
                await self.performSearch()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    @MainActor
    private func beginRequest() -> UUID {
        activeRequestTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        return requestID
    }

    @MainActor
    private func invalidateActiveRequest() {
        activeRequestTask?.cancel()
        activeRequestTask = nil
        activeRequestID = UUID()
    }

    @MainActor
    private func shouldApplyResponse(for requestID: UUID) -> Bool {
        !Task.isCancelled && activeRequestID == requestID
    }

    @MainActor
    private func applySearchResponse(_ response: HansardSearchResponse) {
        activeRequestTask = nil
        perPage = response.perPage
        page = response.page
        total = response.total
        hasMore = Self.computeHasMore(page: response.page, perPage: response.perPage, total: response.total)
        results = response.results
        error = nil
        isLoading = false
    }

    @MainActor
    private func applyLoadMoreResponse(_ response: HansardSearchResponse) {
        activeRequestTask = nil
        perPage = response.perPage
        page = response.page
        total = response.total
        hasMore = Self.computeHasMore(page: response.page, perPage: response.perPage, total: response.total)
        results.append(contentsOf: response.results)
        error = nil
        isLoading = false
    }

    @MainActor
    private func resetSearchState() {
        isLoading = false
        results = []
        error = nil
        page = Constants.firstPage
        hasMore = false
        total = 0
        perPage = Constants.defaultPerPage
    }

    @MainActor
    private func makeLoadMoreContext() -> LoadMoreContext? {
        guard !isLoading else { return nil }
        guard hasMore else { return nil }

        let trimmedQuery = normalizedQuery()
        guard !trimmedQuery.isEmpty else { return nil }

        return LoadMoreContext(
            query: trimmedQuery,
            retainedResults: results,
            currentPage: page,
            currentTotal: total,
            currentHasMore: hasMore,
            nextPage: page + 1
        )
    }

    @MainActor
    private func normalizedQuery() -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeRequestTask(
        query: String,
        page: Int,
        perPage: Int
    ) -> Task<HansardSearchResponse, Error> {
        let service = service
        return Task {
            try Task.checkCancellation()
            let response = try await service.search(
                query: query,
                speaker: nil,
                topic: nil,
                page: page,
                perPage: perPage
            )
            try Task.checkCancellation()
            return response
        }
    }

    private static func computeHasMore(page: Int, perPage: Int, total: Int) -> Bool {
        (page * perPage) < total
    }
}
