//
//  MembersViewModel.swift
//  epac
//

import Observation

@Observable
class MembersViewModel {
	enum MemberStatus: String, CaseIterable {
		case current = "Current"
		case all = "All"
	}

	var searchText: String = ""
	var selectedParty: Party?
	var selectedProvince: Province?
	var selectedStatus: MemberStatus = .current

	var isAnyFilterActive: Bool {
		selectedParty != nil || selectedProvince != nil || selectedStatus != .current
	}

	func filteredMembers(from members: [ParliamentMember]) -> [ParliamentMember] {
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		return members.filter { member in
			let matchesSearch = trimmed.isEmpty
				|| member.name.lowercased().contains(trimmed.lowercased())
				|| member.riding.lowercased().contains(trimmed.lowercased())
			let matchesParty = selectedParty == nil || member.party == selectedParty
			let matchesProvince = selectedProvince == nil || member.province == selectedProvince
			let matchesStatus = selectedStatus == .all || member.toDateTime == nil
			return matchesSearch && matchesParty && matchesProvince && matchesStatus
		}
	}

	func clearAllFilters() {
		selectedParty = nil
		selectedProvince = nil
		selectedStatus = .current
	}
}
