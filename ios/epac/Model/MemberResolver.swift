//
//  MemberResolver.swift
//  epac
//

import SwiftData

// Resolves a SpeechMessage's speaker to a ParliamentMember.
//
// The `MemberResolving` protocol lets callers (SpeechViewModel) and tests
// inject alternate implementations without touching SwiftData.
//
// Uses full-table fetch + in-memory filter rather than #Predicate so this
// file stays free of SwiftData macros (member counts are small, < 400).

@MainActor
protocol MemberResolving {
    func resolve(
        firstName: String,
        lastName: String,
        partyAbbreviation: String,
        ridingName: String,
        parliamentNumber: Int,
        modelContext: ModelContext,
        fetch: Fetch
    ) -> ParliamentMember

    // Clears any in-memory caching state. SpeechViewModel calls this on reset
    // so a new conversation does not bleed speakers from a previous one.
    // Default implementation is a no-op so simple mock types don't need to
    // implement it.
    func resetCache()
}

extension MemberResolving {
    func resetCache() {}
}

@MainActor
struct MemberResolver: MemberResolving {
	func resolve(
		firstName: String,
		lastName: String,
		partyAbbreviation: String,
		ridingName: String,
		parliamentNumber: Int,
		modelContext: ModelContext,
		fetch: Fetch
	) -> ParliamentMember {
		var cache = MemberResolutionCache()
		return cache.resolve(
			firstName: firstName,
			lastName: lastName,
			partyAbbreviation: partyAbbreviation,
			ridingName: ridingName,
			parliamentNumber: parliamentNumber,
			modelContext: modelContext,
			fetch: fetch
		)
	}
}

// Class wrapper so `SpeechViewModel` can hold a session-scoped cache as an
// `any MemberResolving` and pass it as the default resolver — `struct`
// conformance would lose cross-call caching because value-type copies break
// the shared mutable state.
@MainActor
final class CachingMemberResolver: MemberResolving {
	private var cache = MemberResolutionCache()

	func resolve(
		firstName: String,
		lastName: String,
		partyAbbreviation: String,
		ridingName: String,
		parliamentNumber: Int,
		modelContext: ModelContext,
		fetch: Fetch
	) -> ParliamentMember {
		cache.resolve(
			firstName: firstName,
			lastName: lastName,
			partyAbbreviation: partyAbbreviation,
			ridingName: ridingName,
			parliamentNumber: parliamentNumber,
			modelContext: modelContext,
			fetch: fetch
		)
	}

	// Satisfies the MemberResolving.resetCache() requirement.
	func resetCache() { cache.reset() }
}

@MainActor
struct MemberResolutionCache {
	private var didLoadMembers = false
	private var membersByName: [String: ParliamentMember] = [:]
	private var constituencies: [Constituency]?

	mutating func resolve(
		firstName: String,
		lastName: String,
		partyAbbreviation: String,
		ridingName: String,
		parliamentNumber: Int,
		modelContext: ModelContext,
		fetch: Fetch
	) -> ParliamentMember {
		loadMembersIfNeeded(modelContext: modelContext)

		let key = Self.nameKey(firstName: firstName, lastName: lastName)
		if let existing = membersByName[key] {
			return existing
		}

		Task { try? await fetch.downloadMember(firstName, lastName) }

		let constituency = cachedConstituencies(modelContext: modelContext).first(where: {
			!ridingName.isEmpty && ($0.name == ridingName || $0.name.hasPrefix(ridingName))
		})

		let party = Party.partyWithAbbreviation(partyAbbreviation)
		let photoURL = PhotoProvider(parliamentNumber: parliamentNumber)
			.getPhotoURL(lastName: lastName, firstName: firstName, party: party)

		let member = ParliamentMember(
			name: firstName + " " + lastName,
			lastName: lastName,
			firstName: firstName,
			photoURL: photoURL,
			riding: constituency?.name ?? ridingName,
			province: constituency?.province ?? .Ontario,
			party: party
		)
		modelContext.insert(member)
		try? modelContext.save()
		membersByName[key] = member
		return member
	}

	mutating func reset() {
		didLoadMembers = false
		membersByName.removeAll()
		constituencies = nil
	}

	private mutating func loadMembersIfNeeded(modelContext: ModelContext) {
		guard !didLoadMembers else { return }
		let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
		for member in allMembers {
			let key = Self.nameKey(firstName: member.firstName, lastName: member.lastName)
			if membersByName[key] == nil {
				membersByName[key] = member
			}
		}
		didLoadMembers = true
	}

	private mutating func cachedConstituencies(modelContext: ModelContext) -> [Constituency] {
		if let constituencies {
			return constituencies
		}
		let fetched = (try? modelContext.fetch(FetchDescriptor<Constituency>())) ?? []
		constituencies = fetched
		return fetched
	}

	private static func nameKey(firstName: String, lastName: String) -> String {
		"\(firstName)\u{1f}\(lastName)"
	}
}
