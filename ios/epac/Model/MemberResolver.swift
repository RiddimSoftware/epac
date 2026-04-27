//
//  MemberResolver.swift
//  epac
//

import SwiftData

// Resolves a SpeechMessage's speaker to a ParliamentMember.
//
// Looks up by first+last name in SwiftData. If not found, creates a
// temporary member from the message's embedded metadata and triggers
// a background download so the real record appears on the next access.
// Keeping this logic here instead of inline in SpeechViewModel lets
// the resolution strategy be tested and evolved without touching the
// presentation layer.
//
// Uses full-table fetch + in-memory filter rather than #Predicate so this
// file stays free of SwiftData macros (member counts are small, < 400).
@MainActor
struct MemberResolver {
	func resolve(
		firstName: String,
		lastName: String,
		partyAbbreviation: String,
		ridingName: String,
		parliamentNumber: Int,
		modelContext: ModelContext,
		fetch: Fetch
	) -> ParliamentMember {
		let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
		if let existing = allMembers.first(where: { $0.firstName == firstName && $0.lastName == lastName }) {
			return existing
		}

		Task { try? await fetch.downloadMember(firstName, lastName) }

		let allConstituencies = (try? modelContext.fetch(FetchDescriptor<Constituency>())) ?? []
		let constituency = allConstituencies.first(where: {
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
		return member
	}
}
