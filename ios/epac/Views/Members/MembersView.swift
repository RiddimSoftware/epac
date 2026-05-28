//
//  MembersView.swift
//  epac
//
//  Created by Codex on 2025-XX-XX.
//

import SwiftData
import SwiftUI
import UIKit

private enum MembersLayout {
	static let listColumnMinWidth: CGFloat = 320
	static let listColumnIdealWidth: CGFloat = 360
	static let listColumnMaxWidth: CGFloat = 420
	static let selectedRowOpacity = 0.14
	static let sourceBadgeVerticalPadding: CGFloat = 6
	static let activeFilterBadgeMinSize = EpacIconSize.xs
	static let activeFilterBadgeOffset: CGFloat = 7
	static let skeletonRows = 8
	static let memberRowSpacing: CGFloat = 12
	static let memberAvatarSize: CGFloat = 52
	static let memberTextSpacing = EpacSpacing.xxs
	static let badgeStackSpacing: CGFloat = 6
	static let badgeTopPadding = EpacSpacing.xxs
	static let cabinetBadgeSpacing: CGFloat = 3
	static let cabinetBadgeHorizontalPadding: CGFloat = 6
	static let cabinetBadgeVerticalPadding = EpacSpacing.xxs
	static let cabinetBadgeOpacity = 0.15
	static let cabinetBadgeCornerRadius = EpacCornerRadius.xs
	static let popoverMinWidth: CGFloat = 150
}

struct MembersTabRoot: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Binding var selectedMember: ParliamentMember?
	let showMyMPSetup: () -> Void
	@State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
	@State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

	var body: some View {
		if horizontalSizeClass == .compact {
			compactMembersStack
		} else {
			regularMembersSplitView
		}
	}

	private var compactMembersStack: some View {
		NavigationStack {
			MembersView()
				.membersMyMPToolbar(showMyMPSetup)
				.navigationDestination(item: $selectedMember) { member in
					MemberProfileView(member: member)
				}
		}
	}

	private var regularMembersSplitView: some View {
		NavigationSplitView(
			columnVisibility: $columnVisibility,
			preferredCompactColumn: $preferredCompactColumn
		) {
			MembersView(selection: $selectedMember)
				.membersMyMPToolbar(showMyMPSetup)
				.navigationSplitViewColumnWidth(
					min: MembersLayout.listColumnMinWidth,
					ideal: MembersLayout.listColumnIdealWidth,
					max: MembersLayout.listColumnMaxWidth
				)
		} detail: {
			NavigationStack {
				if let selectedMember {
					MemberProfileView(member: selectedMember)
				} else {
					Text("members.detail.placeholder")
						.font(.title3.weight(.semibold))
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.accessibilityIdentifier("members-detail-placeholder")
				}
			}
			.id(selectedMember?.directoryKey)
		}
		.navigationSplitViewStyle(.balanced)
	}
}

struct MembersView: View {
	@Query(sort: [SortDescriptor(\ParliamentMember.lastName, order: .forward)]) private var members: [ParliamentMember]
	@Query private var cabinetPositions: [CabinetPosition]
	@State private var viewModel = MembersViewModel()
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@EnvironmentObject private var fetch: Fetch
	private let selection: Binding<ParliamentMember?>?

	init(selection: Binding<ParliamentMember?>? = nil) {
		self.selection = selection
	}

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
					Section("Filters") {
						Picker("Party", selection: $viewModel.selectedParty) {
							Text("All Parties").tag(Party?.none)
							ForEach(Party.allCases) { party in
								Text(party.shortName).tag(Party?.some(party))
							}
						}

						Picker("Province", selection: $viewModel.selectedProvince) {
							Text("All Provinces").tag(Province?.none)
							ForEach(Province.allCases) { province in
								Text(province.rawValue).tag(Province?.some(province))
							}
						}

						Picker("Status", selection: $viewModel.selectedStatus) {
							ForEach(MembersViewModel.MemberStatus.allCases, id: \.self) { status in
								Text(LocalizedStringKey(status.rawValue)).tag(status)
							}
						}

						Picker("Cabinet", selection: $viewModel.selectedCabinet) {
							ForEach(MembersViewModel.CabinetFilter.allCases, id: \.self) { filter in
								Text(LocalizedStringKey(filter.rawValue)).tag(filter)
							}
						}
						.disabled(cabinetPositions.isEmpty)
					}

					if viewModel.isAnyFilterActive {
						Button(action: viewModel.clearAllFilters) {
							Label("Clear filters", systemImage: "xmark.circle.fill")
						}
					}
				} label: {
					filterToolbarLabel
				}
				.accessibilityLabel(filterAccessibilityLabel)
				.accessibilityIdentifier("members-filter-menu")

				Menu {
					ForEach(Party.allCases) { party in
						PartyMenuLink(party: party)
					}
				} label: {
					Image(systemName: "flag.checkered")
				}
				.accessibilityIdentifier("members-parties-menu")
			}
		}
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				DataSourceBadge(source: .members())
			}
			.padding(.horizontal)
			.padding(.vertical, MembersLayout.sourceBadgeVerticalPadding)
		}
		.navigationTitle("Members")
		.navigationBarTitleDisplayMode(.large)
		.animation(reduceMotion ? nil : .default, value: filteredMembers)
	}

	private var filterToolbarLabel: some View {
		ZStack(alignment: .topTrailing) {
			Image(systemName: viewModel.isAnyFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
			if viewModel.activeFilterCount > 0 {
				Text(verbatim: "\(viewModel.activeFilterCount)")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white)
					.frame(minWidth: MembersLayout.activeFilterBadgeMinSize, minHeight: MembersLayout.activeFilterBadgeMinSize)
					.background(Circle().fill(Color.appDestructive))
					.offset(x: MembersLayout.activeFilterBadgeOffset, y: -MembersLayout.activeFilterBadgeOffset)
					.accessibilityHidden(true)
			}
		}
	}

	private var filterAccessibilityLabel: String {
		if viewModel.activeFilterCount == 0 {
			return "Filters"
		}
		return "Filters, \(viewModel.activeFilterCount) active"
	}

	private var loadingView: some View {
		List {
			ForEach(0..<MembersLayout.skeletonRows, id: \.self) { _ in
				MemberRowSkeleton()
					.shimmer(when: true)
			}
		}
		.listStyle(.plain)
		.accessibilityIdentifier("members-list")
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
					memberRow(for: member)
				}
			}
		}
		.listStyle(.plain)
		.accessibilityIdentifier("members-list")
		.refreshable {
			try? await fetch.downloadMembers()
		}
	}

	@ViewBuilder
	private func memberRow(for member: ParliamentMember) -> some View {
		let isCabinetMinister = ministerKeys.contains(CabinetMatch.key(firstName: member.firstName, lastName: member.lastName))
		if let selection {
			Button {
				MembersSelection.select(member, selection: selection)
			} label: {
				MemberRow(member: member, isCabinetMinister: isCabinetMinister)
			}
			.buttonStyle(.plain)
			.contentShape(Rectangle())
			.listRowBackground(
				MembersSelection.isSelected(member, selectedMember: selection.wrappedValue)
					? Color.accentColor.opacity(MembersLayout.selectedRowOpacity)
					: Color.clear
			)
			.accessibilityAddTraits(
				MembersSelection.isSelected(member, selectedMember: selection.wrappedValue)
					? [.isSelected]
					: []
			)
		} else {
			NavigationLink(destination: MemberProfileView(member: member)) {
				MemberRow(member: member, isCabinetMinister: isCabinetMinister)
			}
		}
	}
}

struct MemberRow: View {
	let member: ParliamentMember
	var isCabinetMinister: Bool = false

	var body: some View {
		HStack(alignment: .center, spacing: MembersLayout.memberRowSpacing) {
			MemberAvatar(member: member)
				.frame(width: MembersLayout.memberAvatarSize, height: MembersLayout.memberAvatarSize)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: MembersLayout.memberTextSpacing) {
				Text(member.name)
					.font(.headline)
				Text(member.riding)
					.font(.subheadline)
					.foregroundColor(.secondary)
				HStack(spacing: MembersLayout.badgeStackSpacing) {
					PartyBadge(party: member.party)
					if isCabinetMinister {
						CabinetMinisterBadge()
					}
				}
				.padding(.top, MembersLayout.badgeTopPadding)
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

enum MembersSelection {
	static func select(_ member: ParliamentMember, selection: Binding<ParliamentMember?>) {
		selection.wrappedValue = member
	}

	static func isSelected(_ member: ParliamentMember, selectedMember: ParliamentMember?) -> Bool {
		member == selectedMember
	}
}

private extension View {
	func membersMyMPToolbar(_ action: @escaping () -> Void) -> some View {
		toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(action: action) {
					Label(NSLocalizedString("riding.myMP.toolbarLabel", comment: ""), systemImage: "mappin.and.ellipse")
				}
				.accessibilityLabel(NSLocalizedString("riding.setup.navTitle", comment: ""))
			}
		}
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
		HStack(spacing: MembersLayout.cabinetBadgeSpacing) {
			Image(systemName: "building.columns.fill")
				.font(.caption2)
			Text("Cabinet")
				.font(.caption2.weight(.semibold))
		}
		.padding(.horizontal, MembersLayout.cabinetBadgeHorizontalPadding)
		.padding(.vertical, MembersLayout.cabinetBadgeVerticalPadding)
		.background(Color.accentColor.opacity(MembersLayout.cabinetBadgeOpacity))
		.foregroundColor(.accentColor)
		.cornerRadius(MembersLayout.cabinetBadgeCornerRadius)
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
		.frame(minWidth: MembersLayout.popoverMinWidth)
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
		.frame(minWidth: MembersLayout.popoverMinWidth)
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
		.frame(minWidth: MembersLayout.popoverMinWidth)
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
