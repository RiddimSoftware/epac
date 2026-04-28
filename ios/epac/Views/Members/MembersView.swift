//
//  MembersView.swift
//  epac
//
//  Created by Codex on 2025-XX-XX.
//

import SwiftUI
import SwiftData
import UIKit

struct MembersView: View {
	@Query(sort: [SortDescriptor(\ParliamentMember.lastName, order: .forward)]) private var members: [ParliamentMember]
	@Query private var cabinetPositions: [CabinetPosition]
	@State private var viewModel = MembersViewModel()
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@EnvironmentObject private var fetch: Fetch

	// Match minister to MP on the (firstName, lastName) pair rather than lastName
	// alone, otherwise common surnames (Thompson, Sidhu, MacDonald, Miller) would
	// false-positive every sitting MP who happens to share a name with a minister.
	// First-name compare uses the leading token only because the snapshot stores
	// "David J." (full given+middle) while ParliamentMember uses "David".
	private var ministerKeys: Set<String> {
		Set(cabinetPositions.map { CabinetMatch.key(firstName: $0.firstName, lastName: $0.lastName) })
	}

	private var filteredMembers: [ParliamentMember] {
		viewModel.filteredMembers(from: members, ministerKeys: ministerKeys)
	}

	var body: some View {
		Group {
			if members.isEmpty {
				loadingView
			} else {
				memberList
			}
		}
		.searchable(
			text: $viewModel.searchText,
			placement: .navigationBarDrawer(displayMode: .always),
			prompt: NSLocalizedString("Search by name or riding", comment: "")
		)
		.toolbar {
			ToolbarItemGroup(placement: .topBarTrailing) {
				Menu {
					Picker("Party", selection: $viewModel.selectedParty) {
						Text("All Parties").tag(Party?.none)
						ForEach(Party.allCases) { party in
							Text(party.shortName).tag(Party?.some(party))
						}
					}
				} label: {
					Image(systemName: viewModel.selectedParty == nil ? "flag" : "flag.fill")
						.foregroundStyle(viewModel.selectedParty.map { Color($0.colour) } ?? .primary)
				}

				Menu {
					Picker("Province", selection: $viewModel.selectedProvince) {
						Text("All Provinces").tag(Province?.none)
						ForEach(Province.allCases) { province in
							Text(province.rawValue).tag(Province?.some(province))
						}
					}
				} label: {
					if let selectedProvince = viewModel.selectedProvince {
						Text(selectedProvince.shortCode)
							.font(.caption)
							.fontWeight(.bold)
							.padding(5)
							.background(Color.accentColor.opacity(0.2))
							.cornerRadius(5)
					} else {
						Image(systemName: "map")
					}
				}

				Menu {
					Picker("Status", selection: $viewModel.selectedStatus) {
						ForEach(MembersViewModel.MemberStatus.allCases, id: \.self) { status in
							Text(LocalizedStringKey(status.rawValue)).tag(status)
						}
					}
				} label: {
					Image(systemName: viewModel.selectedStatus == .all ? "person.2" : "person.fill")
				}

				Menu {
					Picker("Cabinet", selection: $viewModel.selectedCabinet) {
						ForEach(MembersViewModel.CabinetFilter.allCases, id: \.self) { filter in
							Text(LocalizedStringKey(filter.rawValue)).tag(filter)
						}
					}
				} label: {
					Image(systemName: viewModel.selectedCabinet == .cabinetOnly ? "building.columns.fill" : "building.columns")
				}
				.accessibilityIdentifier("members-cabinet-filter")
				.disabled(cabinetPositions.isEmpty)

				Menu {
					ForEach(Party.allCases) { party in
						PartyMenuLink(party: party)
					}
				} label: {
					Image(systemName: "flag.checkered")
				}
				.accessibilityIdentifier("members-parties-menu")

				if viewModel.isAnyFilterActive {
					Button(action: viewModel.clearAllFilters) {
						Image(systemName: "xmark.circle.fill")
					}
				}
			}
		}
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				DataSourceBadge(source: .members())
			}
			.padding(.horizontal)
			.padding(.vertical, 6)
		}
		.navigationTitle("Members")
		.navigationBarTitleDisplayMode(.large)
		.animation(reduceMotion ? nil : .default, value: filteredMembers)
	}

	private var loadingView: some View {
		List {
			ForEach(0..<8, id: \.self) { _ in
				MemberRowSkeleton()
					.shimmer(when: true)
			}
		}
		.listStyle(.plain)
	}

	private var memberList: some View {
		List {
			if filteredMembers.isEmpty {
				if viewModel.isAnyFilterActive {
					ContentUnavailableView {
						Label("No Members Found", systemImage: "person.3.fill")
					} description: {
						Text("No members match your current filter criteria.")
					} actions: {
						Button(action: viewModel.clearAllFilters) {
							Text("Clear Filters")
						}
						.buttonStyle(.borderedProminent)
					}
				} else {
					ContentUnavailableView.search(text: viewModel.searchText)
				}
			} else {
				ForEach(filteredMembers, id: \.id) { member in
					NavigationLink(destination: MemberProfileView(member: member)) {
						MemberRow(member: member, isCabinetMinister: ministerKeys.contains(CabinetMatch.key(firstName: member.firstName, lastName: member.lastName)))
					}
				}
			}
		}
		.listStyle(.plain)
		.refreshable {
			try? await fetch.downloadMembers()
		}
	}
}

struct MemberRow: View {
	let member: ParliamentMember
	var isCabinetMinister: Bool = false

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			MemberAvatar(member: member)
				.frame(width: 52, height: 52)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(member.name)
					.font(.headline)
				Text(member.riding)
					.font(.subheadline)
					.foregroundColor(.secondary)
				HStack(spacing: 6) {
					PartyBadge(party: member.party)
					if isCabinetMinister {
						CabinetMinisterBadge()
					}
				}
				.padding(.top, 2)
			}
			Spacer()
			Text(member.province.rawValue)
				.font(.caption2)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.trailing)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
	}

	private var accessibilityLabel: String {
		let base = "\(member.name), \(member.party.fullName), \(member.riding), \(member.province.rawValue)"
		return isCabinetMinister ? "\(base), Cabinet minister" : base
	}
}

// Shared key builder so MembersView and MemberProfileView match the same way.
// Lowercased "<first-token-of-firstName> <lastName>" — see ministerKeys for why
// we strip the first-name to a leading token.
enum CabinetMatch {
	static func key(firstName: String, lastName: String) -> String {
		let firstToken = firstName.split(separator: " ").first.map(String.init) ?? firstName
		return "\(firstToken.lowercased()) \(lastName.lowercased())"
	}
}

// Menu-row factory: keeps the conditional destination out of the menu
// builder so the parent ViewBuilder type-checks in reasonable time.
private struct PartyMenuLink: View {
	let party: Party

	var body: some View {
		if party == .independent {
			NavigationLink(destination: IndependentsListingView()) {
				Label(party.shortName, systemImage: "flag.fill")
			}
		} else {
			NavigationLink(destination: PartyProfileView(party: party)) {
				Label(party.shortName, systemImage: "flag.fill")
			}
		}
	}
}

struct CabinetMinisterBadge: View {
	var body: some View {
		HStack(spacing: 3) {
			Image(systemName: "building.columns.fill")
				.font(.caption2)
			Text("Cabinet")
				.font(.caption2.weight(.semibold))
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(Color.accentColor.opacity(0.15))
		.foregroundColor(.accentColor)
		.cornerRadius(4)
		.accessibilityIdentifier("cabinet-minister-badge")
	}
}

private struct StatusFilterView: View {
	@Binding var selectedStatus: MembersViewModel.MemberStatus
	@Binding var showingStatusFilter: Bool

	var body: some View {
		VStack {
			List {
				ForEach(MembersViewModel.MemberStatus.allCases, id: \.self) { status in
					Button(action: {
						selectedStatus = status
						showingStatusFilter = false
					}) {
						HStack {
							Text(LocalizedStringKey(status.rawValue))
							Spacer()
							if selectedStatus == status {
								Image(systemName: "checkmark")
							}
						}
					}
					.foregroundColor(.primary)
				}
			}
		}
		.frame(minWidth: 150)
		.presentationCompactAdaptation(.popover)
	}
}

private struct ProvinceFilterView: View {
	@Binding var selectedProvince: Province?
	@Binding var showingProvinceFilter: Bool

	var body: some View {
		VStack {
			List {
				Button(action: {
					selectedProvince = nil
					showingProvinceFilter = false
				}) {
					HStack {
						Text("All Provinces")
						Spacer()
						if selectedProvince == nil {
							Image(systemName: "checkmark")
						}
					}
				}
				.foregroundColor(.primary)
				ForEach(Province.allCases, id: \.self) { province in
					Button(action: {
						selectedProvince = province
						showingProvinceFilter = false
					}) {
						HStack {
							Text(province.rawValue)
							Spacer()
							if selectedProvince == province {
								Image(systemName: "checkmark")
							}
						}
					}
					.foregroundColor(.primary)
				}
			}
		}
		.frame(minWidth: 150)
		.presentationCompactAdaptation(.popover)
	}
}

private struct PartyFilterView: View {
	@Binding var selectedParty: Party?
	@Binding var showingPartyFilter: Bool

	var body: some View {
		VStack {
			List {
				Button(action: {
					selectedParty = nil
					showingPartyFilter = false
				}) {
					HStack {
						Text("All Parties")
						Spacer()
						if selectedParty == nil {
							Image(systemName: "checkmark")
						}
					}
				}
				.foregroundColor(.primary)
				ForEach(Party.allCases, id: \.self) { party in
					Button(action: {
						selectedParty = party
						showingPartyFilter = false
					}) {
						HStack {
							Text(party.shortName)
							Spacer()
							if selectedParty == party {
								Image(systemName: "checkmark")
							}
						}
					}
					.foregroundColor(.primary)
				}
			}
		}
		.frame(minWidth: 150)
		.presentationCompactAdaptation(.popover)
	}
}

#Preview {
	MemberRow(
		member: ParliamentMember(
			name: "Justin Trudeau",
			lastName: "Trudeau",
			firstName: "Justin",
			photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!,
			riding: "Papineau",
			province: .Quebec,
			party: .liberal
		),
		isCabinetMinister: true
	)
}




