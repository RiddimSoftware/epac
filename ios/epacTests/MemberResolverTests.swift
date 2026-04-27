import Testing
import SwiftData
import Foundation
@testable import epac

@MainActor
struct MemberResolverTests {
	private func makeContext() throws -> ModelContext {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
		return ModelContext(container)
	}

	private func makeFetch(_ context: ModelContext) -> Fetch {
		Fetch(modelContainer: context.container)
	}

	@Test func returnsExistingMemberByName() throws {
		let context = try makeContext()
		let existing = ParliamentMember(
			name: "Mark Carney",
			lastName: "Carney",
			firstName: "Mark",
			photoURL: URL(string: "https://example.com/photo.jpg")!,
			riding: "Ottawa South",
			province: Province.Ontario,
			party: Party.liberal
		)
		context.insert(existing)
		try context.save()

		let resolved = MemberResolver().resolve(
			firstName: "Mark",
			lastName: "Carney",
			partyAbbreviation: "Lib",
			ridingName: "Ottawa South",
			parliamentNumber: 45,
			modelContext: context,
			fetch: makeFetch(context)
		)

		#expect(resolved.name == "Mark Carney")
		#expect(resolved.party == Party.liberal)
		let allMembers = try context.fetch(FetchDescriptor<ParliamentMember>())
		#expect(allMembers.count == 1)
	}

	@Test func createsTempMemberWhenNotFound() throws {
		let context = try makeContext()

		let resolved = MemberResolver().resolve(
			firstName: "Jagmeet",
			lastName: "Singh",
			partyAbbreviation: "NDP",
			ridingName: "Burnaby Central",
			parliamentNumber: 45,
			modelContext: context,
			fetch: makeFetch(context)
		)

		#expect(resolved.firstName == "Jagmeet")
		#expect(resolved.lastName == "Singh")
		#expect(resolved.party == Party.newdemocratic)
		#expect(resolved.riding == "Burnaby Central")
		let allMembers = try context.fetch(FetchDescriptor<ParliamentMember>())
		#expect(allMembers.count == 1)
	}

	@Test func usesConstituencyProvinceWhenRidingMatches() throws {
		let context = try makeContext()
		let constituency = Constituency(
			name: "Burnaby Central",
			province: Province.BC,
			currentMemberFirstName: "Jagmeet",
			currentMemberLastName: "Singh",
			currentMemberParty: Party.newdemocratic
		)
		context.insert(constituency)
		try context.save()

		let resolved = MemberResolver().resolve(
			firstName: "Jagmeet",
			lastName: "Singh",
			partyAbbreviation: "NDP",
			ridingName: "Burnaby Central",
			parliamentNumber: 45,
			modelContext: context,
			fetch: makeFetch(context)
		)

		#expect(resolved.province == Province.BC)
	}

	@Test func usesConstituencyProvinceWhenRidingMatchesByPrefix() throws {
		let context = try makeContext()
		// Constituency stored with full riding name; message only contains the prefix
		let constituency = Constituency(
			name: "Burnaby Central",
			province: Province.BC,
			currentMemberFirstName: "Jagmeet",
			currentMemberLastName: "Singh",
			currentMemberParty: Party.newdemocratic
		)
		context.insert(constituency)
		try context.save()

		let resolved = MemberResolver().resolve(
			firstName: "Jagmeet",
			lastName: "Singh",
			partyAbbreviation: "NDP",
			ridingName: "Burnaby",
			parliamentNumber: 45,
			modelContext: context,
			fetch: makeFetch(context)
		)

		#expect(resolved.province == Province.BC)
		#expect(resolved.riding == "Burnaby Central")
	}

	@Test func fallsBackToOntarioWhenNoConstituencyMatch() throws {
		let context = try makeContext()

		let resolved = MemberResolver().resolve(
			firstName: "Pierre",
			lastName: "Poilievre",
			partyAbbreviation: "CPC",
			ridingName: "Carleton",
			parliamentNumber: 45,
			modelContext: context,
			fetch: makeFetch(context)
		)

		#expect(resolved.province == Province.Ontario)
		#expect(resolved.party == Party.conservative)
	}

	@Test func parsesAllPartyAbbreviations() throws {
		let context = try makeContext()
		let fetch = makeFetch(context)
		let resolver = MemberResolver()

		let cases: [(String, Party)] = [
			("Lib", Party.liberal),
			("CPC", Party.conservative),
			("NDP", Party.newdemocratic),
			("BQ", Party.bloc),
			("GP", Party.green),
			("Ind", Party.independent)
		]
		for (abbrev, expectedParty) in cases {
			let member = resolver.resolve(
				firstName: "Test",
				lastName: abbrev,
				partyAbbreviation: abbrev,
				ridingName: "",
				parliamentNumber: 45,
				modelContext: context,
				fetch: fetch
			)
			#expect(member.party == expectedParty)
		}
	}
}
