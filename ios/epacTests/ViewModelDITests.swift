// ViewModelDITests.swift
// epac
//
// Unit tests that verify each ViewModel's dependency injection seam works
// correctly with a mock (no network required).

@testable import epac
import Foundation
import SwiftData
import Testing

// MARK: - Mocks

/// Mock for BrowseHansardSittingUseCase. Runs on MainActor (Sendable via global actor).
@MainActor
private final class MockBrowseHansardSittingUseCase: BrowseHansardSittingUseCase {
    var requests: [(jurisdiction: Jurisdiction, from: Date, to: Date)] = []
    var result = BrowseHansardSitting.Result(sittingDates: [], sittings: [])
    var shouldThrow = false

    func execute(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> BrowseHansardSitting.Result {
        requests.append((jurisdiction, from, to))
        if shouldThrow {
            throw NSError(domain: "MockBrowseHansardSittingUseCase", code: 1)
        }
        return result
    }
}

/// Mock for ExpendituresFetching. Runs on MainActor.
@MainActor
private final class MockExpendituresFetcher: ExpendituresFetching {
    var expendituresCalls: [(year: Int, quarter: Int)] = []
    var downloadCalls: [(year: Int, quarter: Int)] = []
    var shouldThrow = false

    nonisolated func expenditures(year: Int, quarter: Int) async throws {
        await MainActor.run { expendituresCalls.append((year, quarter)) }
        if await MainActor.run(body: { shouldThrow }) {
            throw NSError(domain: "MockExpendituresFetcher", code: 1)
        }
    }

    nonisolated func downloadExpenditures(year: Int, quarter: Int) async throws {
        await MainActor.run { downloadCalls.append((year, quarter)) }
        if await MainActor.run(body: { shouldThrow }) {
            throw NSError(domain: "MockExpendituresFetcher", code: 1)
        }
    }
}

/// Mock for MemberResolving. Class so identity is preserved when stored as `any MemberResolving`.
@MainActor
private final class MockMemberResolver: MemberResolving {
    let stubbedMember: ParliamentMember
    private(set) var resetCacheCallCount = 0

    init(stubbedMember: ParliamentMember) {
        self.stubbedMember = stubbedMember
    }

    func resolve(
        firstName: String, lastName: String,
        partyAbbreviation: String, ridingName: String,
        parliamentNumber: Int, modelContext: ModelContext, fetch: Fetch
    ) -> ParliamentMember {
        stubbedMember
    }

    func resetCache() { resetCacheCallCount += 1 }
}

// MARK: - SittingCalendarViewModel DI

@MainActor
struct SittingCalendarViewModelDITests {

    private func makeDependencies() throws -> (ModelContainer, ModelContext, Fetch) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
        let context = ModelContext(container)
        return (container, context, Fetch(modelContainer: container))
    }

    /// Injected use case is called instead of direct calendar/network orchestration.
    @Test func fetchSittingCalendarUsesInjectedBrowseUseCase() async throws {
        let (_, context, fetch) = try makeDependencies()
        let mockUseCase = MockBrowseHansardSittingUseCase()
        let sitting = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 1))!
        mockUseCase.result = BrowseHansardSitting.Result(sittingDates: [sitting], sittings: [])
        let vm = SittingCalendarViewModel(browseHansardSitting: mockUseCase)

        await vm.fetchSittingCalendar(2026, modelContext: context, fetch: fetch)

        #expect(mockUseCase.requests.map(\.jurisdiction) == [.houseOfCommons])
        #expect(vm.dates.union(vm.futureDates).count == 1)
        #expect(!vm.loadFailed)
    }

    /// When the injected use case throws, loadFailed is set.
    @Test func fetchSittingCalendarSetsLoadFailedOnError() async throws {
        let (_, context, fetch) = try makeDependencies()
        let mockUseCase = MockBrowseHansardSittingUseCase()
        mockUseCase.shouldThrow = true
        let vm = SittingCalendarViewModel(browseHansardSitting: mockUseCase)

        await vm.fetchSittingCalendar(2026, modelContext: context, fetch: fetch)

        #expect(vm.loadFailed)
    }

    /// refresh() uses the injected use case, not direct calendar orchestration.
    @Test func refreshUsesInjectedBrowseUseCase() async throws {
        let (_, context, fetch) = try makeDependencies()
        let mockUseCase = MockBrowseHansardSittingUseCase()
        let vm = SittingCalendarViewModel(browseHansardSitting: mockUseCase)

        await vm.refresh(modelContext: context, fetch: fetch)

        #expect(mockUseCase.requests.count == 1)
        #expect(!vm.loadFailed)
    }
}

// MARK: - ExpendituresViewModel DI

@MainActor
struct ExpendituresViewModelDITests {

    /// When no cached data exists, loadData calls expenditures() on the injected mock.
    @Test func loadDataCallsMockWhenNoCachedData() async throws {
        let mockFetcher = MockExpendituresFetcher()
        let vm = ExpendituresViewModel()
        vm.selectedYear = 2024
        vm.selectedQuarter = 1

        await vm.loadData(expenditures: [], fetch: mockFetcher)

        #expect(mockFetcher.expendituresCalls.count == 1)
        #expect(mockFetcher.expendituresCalls[0].year == 2024)
        #expect(mockFetcher.expendituresCalls[0].quarter == 1)
    }

    /// When cached data already exists for the period, loadData skips the fetch.
    @Test func loadDataSkipsMockWhenDataCached() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
        let context = ModelContext(container)
        let mockFetcher = MockExpendituresFetcher()

        let vm = ExpendituresViewModel()
        vm.selectedYear = 2024
        vm.selectedQuarter = 1

        let cached = SummaryExpenditure(
            firstName: "Alice", lastName: "Smith",
            constituency: "Test", caucus: "Lib",
            salaries: 0, travel: 100, hospitality: 0, contracts: 0,
            year: 2024, quarter: 1
        )
        context.insert(cached)

        await vm.loadData(expenditures: [cached], fetch: mockFetcher)

        #expect(mockFetcher.expendituresCalls.isEmpty)
    }

    /// refresh() calls downloadExpenditures on the injected mock.
    @Test func refreshCallsMockDownload() async throws {
        let mockFetcher = MockExpendituresFetcher()
        let vm = ExpendituresViewModel()
        vm.selectedYear = 2023
        vm.selectedQuarter = 3

        await vm.refresh(fetch: mockFetcher)

        #expect(mockFetcher.downloadCalls.count == 1)
        #expect(mockFetcher.downloadCalls[0].year == 2023)
        #expect(mockFetcher.downloadCalls[0].quarter == 3)
    }

    /// When the mock throws on refresh, loadFailed is set.
    @Test func refreshSetsLoadFailedOnMockError() async throws {
        let mockFetcher = MockExpendituresFetcher()
        mockFetcher.shouldThrow = true
        let vm = ExpendituresViewModel()

        await vm.refresh(fetch: mockFetcher)

        #expect(vm.loadFailed)
        #expect(!vm.isLoading)
    }
}

// MARK: - SpeechViewModel DI

@MainActor
struct SpeechViewModelDITests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
    }

    private func stubMember() -> ParliamentMember {
        ParliamentMember(
            name: "Stub Member",
            lastName: "Member",
            firstName: "Stub",
            // swiftlint:disable:next force_unwrapping
            photoURL: URL(string: "https://example.com/photo.jpg")!,
            riding: "Mock Riding",
            province: .Ontario,
            party: .liberal
        )
    }

    private func makeHansardWithOneMessage() throws -> (ModelContainer, ModelContext, Hansard, SubjectOfBusiness) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let message = SpeechMessage(
            firstName: "Speaker0", lastName: "Last0",
            partyAbbreviation: "Lib", ridingName: "Riding0",
            hansardID: "msg-0001", content: "Hello", timestamp: Date()
        )
        let speech = Speech(messages: [message], hansardID: "sp-0", date: Date(), title: "T")
        let subject = SubjectOfBusiness(title: "T", hansardID: "sub-0", speeches: [speech])
        let order = OrderOfBusiness(hansardID: "o-0", catchline: "R", subjects: [subject])
        let hansard = Hansard(date: Date(), hansardID: "h-0", parliamentNumber: 45, sessionNumber: 1, orders: [order])
        context.insert(hansard)
        try context.save()
        return (container, context, hansard, subject)
    }

    /// Injected mock resolver is used by nextMessage when no method-level override is passed.
    @Test func initInjectedResolverIsUsedByNextMessage() throws {
        let (container, context, hansard, subject) = try makeHansardWithOneMessage()
        let fetch = Fetch(modelContainer: container)
        let stub = stubMember()
        let mockResolver = MockMemberResolver(stubbedMember: stub)

        // Inject resolver at init — the key DI contract.
        let vm = SpeechViewModel(resolver: mockResolver)
        let navigator = SubjectNavigator(subject)

        // No method-level resolver override → init-injected mock is used.
        vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard,
                       modelContext: context, fetch: fetch)

        #expect(vm.messages.first?.user.name == "Stub Member")
    }

    /// Verify reset() propagates resetCache() to the injected resolver.
    @Test func resetCallsResetCacheOnInjectedResolver() throws {
        let (container, context, hansard, subject) = try makeHansardWithOneMessage()
        let fetch = Fetch(modelContainer: container)
        let mockResolver = MockMemberResolver(stubbedMember: stubMember())
        let vm = SpeechViewModel(resolver: mockResolver)
        let navigator = SubjectNavigator(subject)

        vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard,
                       modelContext: context, fetch: fetch)
        vm.reset(navigator: navigator, subject: subject)

        #expect(vm.messages.isEmpty)
        #expect(mockResolver.resetCacheCallCount == 1)
    }
}

// MARK: - MembersViewModel no-network test

// MembersViewModel has no service dependency — its data arrives via SwiftData
// @Query in the view. These tests confirm filter logic is fully testable
// without a Fetch actor or network.
@MainActor
struct MembersViewModelNoNetworkTests {

    /// filteredMembers works with plain in-memory ParliamentMember values — no service needed.
    @Test func filteredMembersRequiresNoNetworkOrService() {
        let vm = MembersViewModel()

        // swiftlint:disable:next force_unwrapping
        let photoURL = URL(string: "https://example.com/photo.jpg")!
        let trudeau = ParliamentMember(
            name: "Justin Trudeau", lastName: "Trudeau", firstName: "Justin",
            photoURL: photoURL, riding: "Papineau", province: .Quebec, party: .liberal
        )
        let poilievre = ParliamentMember(
            name: "Pierre Poilievre", lastName: "Poilievre", firstName: "Pierre",
            photoURL: photoURL, riding: "Carleton", province: .Ontario, party: .conservative
        )

        vm.selectedParty = .liberal
        let result = vm.filteredMembers(from: [trudeau, poilievre])

        #expect(result.count == 1)
        #expect(result.first?.party == .liberal)
    }

    /// Cabinet filter works without a network or Fetch dependency.
    @Test func cabinetFilterWorksWithInMemoryMinisterKeys() {
        let vm = MembersViewModel()
        vm.selectedCabinet = .cabinetOnly

        // swiftlint:disable:next force_unwrapping
        let photoURL = URL(string: "https://example.com/photo.jpg")!
        let minister = ParliamentMember(
            name: "Mark Carney", lastName: "Carney", firstName: "Mark",
            photoURL: photoURL, riding: "Ottawa South", province: .Ontario, party: .liberal
        )
        let backbencher = ParliamentMember(
            name: "Jane Doe", lastName: "Doe", firstName: "Jane",
            photoURL: photoURL, riding: "Test Riding", province: .Ontario, party: .liberal
        )

        let ministerKey = CabinetMatch.key(firstName: "Mark", lastName: "Carney")
        let result = vm.filteredMembers(from: [minister, backbencher], ministerKeys: [ministerKey])

        #expect(result.count == 1)
        #expect(result.first?.lastName == "Carney")
    }
}
