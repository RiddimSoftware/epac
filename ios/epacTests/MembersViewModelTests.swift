import Testing
import SwiftData
import Foundation
@testable import epac

// MembersViewModel holds no SwiftData state itself — its filteredMembers(from:)
// and clearAllFilters() operate on plain values. We still create ParliamentMember
// instances via an in-memory container to stay consistent with SwiftData's
// @Model contract.
struct MembersViewModelTests {

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV3.models), configurations: config)
	}

	private func member(
		firstName: String, lastName: String,
		party: Party, province: Province,
		riding: String = "Test Riding",
		isCurrent: Bool = true,
		context: ModelContext
	) -> ParliamentMember {
		let m = ParliamentMember(
			name: firstName + " " + lastName,
			lastName: lastName,
			firstName: firstName,
			photoURL: URL(string: "https://example.com/photo.jpg")!,
			riding: riding,
			province: province,
			party: party,
			toDateTime: isCurrent ? nil : Date(timeIntervalSince1970: 0)
		)
		context.insert(m)
		return m
	}

	// MARK: - filteredMembers — search text

	@Test func emptySearchReturnsAllCurrentMembers() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Justin", lastName: "Trudeau", party: .liberal, province: .Ontario, context: ctx),
			member(firstName: "Pierre", lastName: "Poilievre", party: .conservative, province: .Ontario, context: ctx)
		]
		#expect(vm.filteredMembers(from: members).count == 2)
	}

	@Test func searchMatchesName() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Justin", lastName: "Trudeau", party: .liberal, province: .Ontario, context: ctx),
			member(firstName: "Pierre", lastName: "Poilievre", party: .conservative, province: .Ontario, context: ctx)
		]
		vm.searchText = "trud"
		let result = vm.filteredMembers(from: members)
		#expect(result.count == 1)
		#expect(result.first?.lastName == "Trudeau")
	}

	@Test func searchMatchesRiding() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Justin", lastName: "Trudeau", party: .liberal, province: .Quebec, riding: "Papineau", context: ctx),
			member(firstName: "Pierre", lastName: "Poilievre", party: .conservative, province: .Ontario, riding: "Carleton", context: ctx)
		]
		vm.searchText = "carle"
		let result = vm.filteredMembers(from: members)
		#expect(result.count == 1)
		#expect(result.first?.lastName == "Poilievre")
	}

	@Test func searchIsCaseInsensitive() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Justin", lastName: "Trudeau", party: .liberal, province: .Ontario, context: ctx)
		]
		vm.searchText = "TRUDEAU"
		#expect(vm.filteredMembers(from: members).count == 1)
	}

	// MARK: - filteredMembers — party filter

	@Test func filterByPartyExcludesOtherParties() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Justin", lastName: "Trudeau", party: .liberal, province: .Ontario, context: ctx),
			member(firstName: "Pierre", lastName: "Poilievre", party: .conservative, province: .Ontario, context: ctx),
			member(firstName: "Jagmeet", lastName: "Singh", party: .newdemocratic, province: .BC, context: ctx)
		]
		vm.selectedParty = .liberal
		let result = vm.filteredMembers(from: members)
		#expect(result.count == 1)
		#expect(result.first?.party == Party.liberal)
	}

	// MARK: - filteredMembers — province filter

	@Test func filterByProvinceExcludesOtherProvinces() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "A", lastName: "Ontario", party: .liberal, province: .Ontario, context: ctx),
			member(firstName: "B", lastName: "BC", party: .liberal, province: .BC, context: ctx),
			member(firstName: "C", lastName: "Quebec", party: .liberal, province: .Quebec, context: ctx)
		]
		vm.selectedProvince = Province.BC
		let result = vm.filteredMembers(from: members)
		#expect(result.count == 1)
		#expect(result.first?.province == Province.BC)
	}

	// MARK: - filteredMembers — status filter

	@Test func defaultStatusShowsOnlyCurrentMembers() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Current", lastName: "MP", party: .liberal, province: .Ontario, isCurrent: true, context: ctx),
			member(firstName: "Former", lastName: "MP", party: .liberal, province: .Ontario, isCurrent: false, context: ctx)
		]
		// selectedStatus defaults to .current
		let result = vm.filteredMembers(from: members)
		#expect(result.count == 1)
		#expect(result.first?.firstName == "Current")
	}

	@Test func allStatusShowsCurrentAndFormerMembers() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Current", lastName: "MP", party: .liberal, province: .Ontario, isCurrent: true, context: ctx),
			member(firstName: "Former", lastName: "MP", party: .liberal, province: .Ontario, isCurrent: false, context: ctx)
		]
		vm.selectedStatus = .all
		#expect(vm.filteredMembers(from: members).count == 2)
	}

	// MARK: - filteredMembers — combined filters

	@Test func combinedPartyAndProvinceFilter() throws {
		let ctx = ModelContext(try makeContainer())
		let vm = MembersViewModel()
		let members = [
			member(firstName: "Liberal", lastName: "Ontario", party: .liberal, province: .Ontario, context: ctx),
			member(firstName: "Liberal", lastName: "BC", party: .liberal, province: .BC, context: ctx),
			member(firstName: "Conservative", lastName: "Ontario", party: .conservative, province: .Ontario, context: ctx)
		]
		vm.selectedParty = .liberal
		vm.selectedProvince = Province.Ontario
		let result = vm.filteredMembers(from: members)
		#expect(result.count == 1)
		#expect(result.first?.lastName == "Ontario")
		#expect(result.first?.party == Party.liberal)
	}

	// MARK: - isAnyFilterActive

	@Test func isAnyFilterActiveIsFalseByDefault() {
		let vm = MembersViewModel()
		#expect(!vm.isAnyFilterActive)
	}

	@Test func isAnyFilterActiveIsTrueWhenPartySelected() {
		let vm = MembersViewModel()
		vm.selectedParty = .liberal
		#expect(vm.isAnyFilterActive)
	}

	@Test func isAnyFilterActiveIsTrueWhenProvinceSelected() {
		let vm = MembersViewModel()
		vm.selectedProvince = Province.Quebec
		#expect(vm.isAnyFilterActive)
	}

	@Test func isAnyFilterActiveIsTrueWhenStatusIsAll() {
		let vm = MembersViewModel()
		vm.selectedStatus = .all
		#expect(vm.isAnyFilterActive)
	}

	// MARK: - clearAllFilters

	@Test func clearAllFiltersResetsToDefaults() {
		let vm = MembersViewModel()
		vm.selectedParty = .liberal
		vm.selectedProvince = Province.Ontario
		vm.selectedStatus = .all

		vm.clearAllFilters()

		#expect(vm.selectedParty == nil)
		#expect(vm.selectedProvince == nil)
		#expect(vm.selectedStatus == .current)
		#expect(!vm.isAnyFilterActive)
	}
}
