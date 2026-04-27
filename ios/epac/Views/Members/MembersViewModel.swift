//
//  MembersViewModel.swift
//  epac
//

import Observation

@MainActor
@Observable
class MembersViewModel {
    enum MemberStatus: String, CaseIterable {
        case current = "Current"
        case all = "All"
    }

    var searchText: String = "" { didSet { invalidate() } }
    var selectedParty: Party? { didSet { invalidate() } }
    var selectedProvince: Province? { didSet { invalidate() } }
    var selectedStatus: MemberStatus = .current { didSet { invalidate() } }

    var isAnyFilterActive: Bool {
        selectedParty != nil || selectedProvince != nil || selectedStatus != .current
    }

    // Memoized filtered list — recomputed only when filter inputs change, not on every render.
    private var cachedResult: [ParliamentMember] = []
    private var cachedSource: [ParliamentMember] = []
    private var dirty = true

    func filteredMembers(from members: [ParliamentMember]) -> [ParliamentMember] {
        // If inputs haven't changed since last call, return the cached result.
        if !dirty && cachedSource.count == members.count {
            return cachedResult
        }
        dirty = false
        cachedSource = members
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cachedResult = members.filter { member in
            let matchesSearch = trimmed.isEmpty
                || member.name.lowercased().contains(trimmed)
                || member.riding.lowercased().contains(trimmed)
            let matchesParty = selectedParty == nil || member.party == selectedParty
            let matchesProvince = selectedProvince == nil || member.province == selectedProvince
            let matchesStatus = selectedStatus == .all || member.toDateTime == nil
            return matchesSearch && matchesParty && matchesProvince && matchesStatus
        }
        return cachedResult
    }

    func clearAllFilters() {
        selectedParty = nil
        selectedProvince = nil
        selectedStatus = .current
    }

    private func invalidate() { dirty = true }
}
