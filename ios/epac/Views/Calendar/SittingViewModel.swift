//
//  SittingViewModel.swift
//  epac
//

import Observation

@Observable
class SittingViewModel {
	func getMember(_ firstName: String, _ lastName: String, from members: [ParliamentMember], fetch: Fetch) -> ParliamentMember? {
		if let member = members.first(where: { $0.firstName == firstName && $0.lastName == lastName }) {
			return member
		}
		Task {
			try? await fetch.downloadMember(firstName, lastName)
		}
		return nil
	}

	func speakers(for subject: SubjectOfBusiness, from members: [ParliamentMember], fetch: Fetch) -> [ParliamentMember] {
		let speakers = subject.speeches
			.compactMap { $0.messages.first }
			.compactMap { getMember($0.firstName, $0.lastName, from: members, fetch: fetch) }
		return Array(Set(speakers)).sorted(by: { $0.lastName < $1.lastName })
	}
}
