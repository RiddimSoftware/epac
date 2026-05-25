@testable import epac
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct HansardSearchViewModelTests {
    @Test func initialStateMatchesTicketContract() {
        let viewModel = HansardSearchViewModel(service: FakeHansardSearchService())

        #expect(viewModel.query.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.error == nil)
        #expect(viewModel.page == 1)
        #expect(!viewModel.hasMore)
        #expect(viewModel.total == 0)
    }

    @Test func searchPopulatesResultsTotalAndHasMore() async {
        let response = makeResponse(
            page: 1,
            perPage: 20,
            total: 25,
            results: [makeResult(messageID: "msg-1")]
        )
        let service = FakeHansardSearchService(steps: [.success(response)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        await viewModel.search()

        #expect(!viewModel.isLoading)
        #expect(viewModel.results == response.results)
        #expect(viewModel.total == 25)
        #expect(viewModel.page == 1)
        #expect(viewModel.hasMore)
        #expect(viewModel.error == nil)
    }

    @Test func loadMoreAppendsResultsAndAdvancesPage() async {
        let firstPage = makeResponse(
            page: 1,
            perPage: 20,
            total: 21,
            results: [makeResult(messageID: "msg-1")]
        )
        let secondPage = makeResponse(
            page: 2,
            perPage: 20,
            total: 21,
            results: [makeResult(messageID: "msg-2")]
        )
        let service = FakeHansardSearchService(steps: [.success(firstPage), .success(secondPage)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        await viewModel.search()
        await viewModel.loadMore()

        #expect(viewModel.results.map(\.messageID) == ["msg-1", "msg-2"])
        #expect(viewModel.page == 2)
        #expect(viewModel.total == 21)
        #expect(!viewModel.hasMore)
        #expect(viewModel.error == nil)
    }

    @Test func loadMoreIsNoOpWhenHasMoreIsFalse() async {
        let response = makeResponse(
            page: 1,
            perPage: 20,
            total: 1,
            results: [makeResult(messageID: "msg-1")]
        )
        let service = FakeHansardSearchService(steps: [.success(response)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        await viewModel.search()
        await viewModel.loadMore()

        #expect(await service.requestCount() == 1)
        #expect(viewModel.results == response.results)
        #expect(viewModel.page == 1)
    }

    @Test func loadMoreErrorRetainsPriorResultsAndClearsLoading() async {
        let response = makeResponse(
            page: 1,
            perPage: 20,
            total: 21,
            results: [makeResult(messageID: "msg-1")]
        )
        let service = FakeHansardSearchService(steps: [.success(response), .failure(.boom)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        await viewModel.search()
        await viewModel.loadMore()

        #expect(viewModel.results == response.results)
        #expect(viewModel.page == 1)
        #expect(viewModel.total == 21)
        #expect(viewModel.hasMore)
        #expect(!viewModel.isLoading)
        #expect((viewModel.error as? TestError) == .boom)
    }

    @Test func secondSearchCancelsFirstPendingRequest() async {
        let secondResponse = makeResponse(
            page: 1,
            perPage: 20,
            total: 1,
            results: [makeResult(messageID: "msg-2", topic: "Climate")]
        )
        let service = FakeHansardSearchService(steps: [.blockUntilCancelled, .success(secondResponse)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        let firstSearch = Task { await viewModel.search() }
        await service.waitForRequestCount(1)

        viewModel.query = "climate"
        let secondSearch = Task { await viewModel.search() }

        await secondSearch.value
        await firstSearch.value

        #expect(await service.cancellationCount() == 1)
        #expect(await service.lastRequest()?.query == "climate")
        #expect(viewModel.results == secondResponse.results)
        #expect((viewModel.error as? TestError) == nil)
        #expect(!viewModel.isLoading)
    }

    @Test func queryChangesDebounceBeforeAutomaticSearch() async throws {
        let response = makeResponse(
            page: 1,
            perPage: 20,
            total: 1,
            results: [makeResult(messageID: "msg-1")]
        )
        let service = FakeHansardSearchService(steps: [.success(response)])
        let viewModel = HansardSearchViewModel(
            service: service,
            debounceDuration: .milliseconds(50)
        )

        viewModel.query = "hous"
        try await Task.sleep(for: .milliseconds(10))
        viewModel.query = "housing"

        #expect(await service.requestCount() == 0)

        try await Task.sleep(for: .milliseconds(80))

        #expect(await service.requestCount() == 1)
        #expect(await service.lastRequest()?.query == "housing")
        #expect(viewModel.results == response.results)
    }

    @Test func emptyResultsKeepHasMoreFalse() async {
        let response = makeResponse(page: 1, perPage: 20, total: 0, results: [])
        let service = FakeHansardSearchService(steps: [.success(response)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        await viewModel.search()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.total == 0)
        #expect(!viewModel.hasMore)
        #expect(viewModel.page == 1)
    }

    @Test func clearResetsState() async {
        let response = makeResponse(
            page: 1,
            perPage: 20,
            total: 1,
            results: [makeResult(messageID: "msg-1")]
        )
        let service = FakeHansardSearchService(steps: [.success(response)])
        let viewModel = HansardSearchViewModel(service: service)
        viewModel.query = "housing"

        await viewModel.search()
        viewModel.clear()

        #expect(viewModel.query.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.error == nil)
        #expect(viewModel.page == 1)
        #expect(!viewModel.hasMore)
        #expect(viewModel.total == 0)
    }

    private func makeResponse(
        page: Int,
        perPage: Int,
        total: Int,
        results: [HansardSearchResult]
    ) -> HansardSearchResponse {
        HansardSearchResponse(page: page, perPage: perPage, total: total, results: results)
    }

    private func makeResult(
        messageID: String,
        topic: String = "Housing"
    ) -> HansardSearchResult {
        HansardSearchResult(
            parliamentNumber: 45,
            sessionNumber: 1,
            sittingDate: Date(timeIntervalSince1970: 1_700_000_000),
            interventionID: "int-\(messageID)",
            messageID: messageID,
            speakerName: "Jane Example",
            partyAbbreviation: "LIB",
            ridingName: "Example Centre",
            topic: topic,
            snippet: "Snippet for \(messageID)",
            score: 0.9
        )
    }
}

private enum TestError: Error, Equatable, Sendable {
    case boom
}

private actor FakeHansardSearchService: HansardSearchProviding {
    struct Request: Equatable, Sendable {
        let query: String
        let page: Int
        let perPage: Int
    }

    enum Step: Sendable {
        case success(HansardSearchResponse)
        case failure(TestError)
        case blockUntilCancelled
    }

    private enum ServiceError: Error, Sendable {
        case missingStep
    }

    private var steps: [Step]
    private var requests: [Request] = []
    private var blockedContinuations: [CheckedContinuation<HansardSearchResponse, Error>] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancellations = 0

    init(steps: [Step] = []) {
        self.steps = steps
    }

    func search(
        query: String,
        speaker: String?,
        topic: String?,
        page: Int,
        perPage: Int
    ) async throws -> HansardSearchResponse {
        requests.append(Request(query: query, page: page, perPage: perPage))
        resumeRequestWaitersIfNeeded()

        guard !steps.isEmpty else {
            throw ServiceError.missingStep
        }

        let step = steps.removeFirst()
        switch step {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        case .blockUntilCancelled:
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    blockedContinuations.append(continuation)
                }
            } onCancel: {
                Task { await self.resumeBlockedRequestWithCancellation() }
            }
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func requestCount() -> Int {
        requests.count
    }

    func lastRequest() -> Request? {
        requests.last
    }

    func cancellationCount() -> Int {
        cancellations
    }

    private func resumeRequestWaitersIfNeeded() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in requestWaiters {
            if requests.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        requestWaiters = remaining
    }

    private func resumeBlockedRequestWithCancellation() {
        cancellations += 1
        guard !blockedContinuations.isEmpty else { return }
        let continuation = blockedContinuations.removeFirst()
        continuation.resume(throwing: CancellationError())
    }
}
