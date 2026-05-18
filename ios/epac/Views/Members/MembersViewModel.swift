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

    enum CabinetFilter: String, CaseIterable {
        case all = "All Members"
        case cabinetOnly = "Cabinet Ministers"
    }

    var searchText: String = "" { didSet { invalidate() } }
    var selectedParty: Party? { didSet { invalidate() } }
    var selectedProvince: Province? { didSet { invalidate() } }
    var selectedStatus: MemberStatus = .current { didSet { invalidate() } }
    var selectedCabinet: CabinetFilter = .all { didSet { invalidate() } }

    var isAnyFilterActive: Bool {
        selectedParty != nil || selectedProvince != nil || selectedStatus != .current || selectedCabinet != .all
    }

    var activeFilterCount: Int {
        [
            selectedParty != nil,
            selectedProvince != nil,
            selectedStatus != .current,
            selectedCabinet != .all
        ].filter { $0 }.count
    }

    // Memoized filtered list — recomputed only when filter inputs change, not on every render.
    private var cachedResult: [ParliamentMember] = []
    private var cachedSource: [ParliamentMember] = []
    private var cachedMinisterCount: Int = -1
    private var dirty = true

    func filteredMembers(from members: [ParliamentMember], ministerKeys: Set<String> = []) -> [ParliamentMember] {
        // If inputs haven't changed since last call, return the cached result.
        if !dirty && cachedSource.count == members.count && cachedMinisterCount == ministerKeys.count {
            return cachedResult
        }
        dirty = false
        cachedSource = members
        cachedMinisterCount = ministerKeys.count
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cachedResult = members.filter { member in
            let matchesSearch = trimmed.isEmpty
                || member.name.lowercased().contains(trimmed)
                || member.riding.lowercased().contains(trimmed)
            let matchesParty = selectedParty == nil || member.party == selectedParty
            let matchesProvince = selectedProvince == nil || member.province == selectedProvince
            let matchesStatus = selectedStatus == .all || member.toDateTime == nil
            let matchesCabinet = selectedCabinet == .all
                || ministerKeys.contains(CabinetMatch.key(firstName: member.firstName, lastName: member.lastName))
            return matchesSearch && matchesParty && matchesProvince && matchesStatus && matchesCabinet
        }
        return cachedResult
    }

    func clearAllFilters() {
        selectedParty = nil
        selectedProvince = nil
        selectedStatus = .current
        selectedCabinet = .all
    }

    private func invalidate() { dirty = true }
}
