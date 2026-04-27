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
	@State private var viewModel = MembersViewModel()
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@EnvironmentObject private var fetch: Fetch

	private var filteredMembers: [ParliamentMember] {
		viewModel.filteredMembers(from: members)
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
						MemberRow(member: member)
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
				PartyBadge(party: member.party)
					.padding(.top, 2)
			}
			Spacer()
			Text(member.province.rawValue)
				.font(.caption2)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.trailing)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(member.name), \(member.party.fullName), \(member.riding), \(member.province.rawValue)")
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
		)
	)
}




