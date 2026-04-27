//
//  MemberProfileView.swift
//  epac
//
//  Created by Codex on 2026-01-28.
//

import SwiftUI
import SwiftData

struct MemberProfileView: View {
	let member: ParliamentMember

	@EnvironmentObject private var fetch: Fetch
	@Query(sort: [SortDescriptor(\ParliamentMember.lastName)]) private var allMembers: [ParliamentMember]
	@State private var showingComparePicker = false
	@State private var comparisonTarget: ParliamentMember?
	@State private var navigateToComparison = false
	@State private var pickerSearch = ""
	@State private var showVotingHistory = false

	init(member: ParliamentMember) {
		self.member = member
	}

	private var contactSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let email = member.email, let url = URL(string: "mailto:\(email)") {
				Button { UIApplication.shared.open(url) } label: {
					ProfileDetailRow(icon: "envelope.fill", label: NSLocalizedString("contact.email", comment: ""), value: email)
				}
				.foregroundStyle(.primary)
			}
			if let phone = member.hillPhone,
			   let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
				Button { UIApplication.shared.open(url) } label: {
					ProfileDetailRow(icon: "phone.fill", label: NSLocalizedString("contact.hillOffice", comment: ""), value: phone)
				}
				.foregroundStyle(.primary)
			}
			if let phone = member.constituencyPhone,
			   let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
				Button { UIApplication.shared.open(url) } label: {
					ProfileDetailRow(icon: "phone.fill", label: NSLocalizedString("contact.constituencyPhone", comment: ""), value: phone)
				}
				.foregroundStyle(.primary)
			}
			if let address = member.constituencyAddress {
				ProfileDetailRow(icon: "building.2.fill", label: NSLocalizedString("contact.constituencyAddress", comment: ""), value: address)
			}
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(12)
	}

	private var pickableMembers: [ParliamentMember] {
		let trimmed = pickerSearch.trimmingCharacters(in: .whitespaces)
		let others = allMembers.filter { $0.name != member.name }
		guard !trimmed.isEmpty else { return others }
		return others.filter {
			$0.name.localizedCaseInsensitiveContains(trimmed) ||
			$0.riding.localizedCaseInsensitiveContains(trimmed)
		}
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .center, spacing: 20) {
				MemberAvatar(member: member)
					.frame(width: 150, height: 150)
					.padding(.top, 20)

				VStack(alignment: .leading, spacing: 10) {
					ProfileDetailRow(icon: "flag.fill", label: "Party", value: member.party.fullName)
					ProfileDetailRow(icon: "mappin.and.ellipse", label: "Riding", value: member.riding)
					ProfileDetailRow(icon: "location.fill", label: "Province", value: member.province.rawValue)
				}
				.padding()
				.background(Color(.secondarySystemBackground))
				.cornerRadius(12)

				if member.email != nil || member.hillPhone != nil || member.constituencyPhone != nil || member.constituencyAddress != nil {
					contactSection
				}
			}
			.padding()
		}
		.task(id: member.memberID) {
			try? await fetch.downloadMemberContact(identifier: member.persistentModelID)
		}
		.navigationTitle(member.name)
		.navigationBarTitleDisplayMode(.large)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				Button {
					showVotingHistory = true
				} label: {
					Label(NSLocalizedString("votes.toolbarLabel", comment: ""), systemImage: "hand.raised")
				}
				.accessibilityLabel(NSLocalizedString("votes.navTitle", comment: ""))
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					pickerSearch = ""
					showingComparePicker = true
				} label: {
					Label("Compare", systemImage: "person.2.badge.gearshape")
				}
				.accessibilityLabel("Compare with another member")
			}
		}
		.navigationDestination(isPresented: $navigateToComparison) {
			if let other = comparisonTarget {
				MemberComparisonView(memberA: member, memberB: other)
			}
		}
		.navigationDestination(isPresented: $showVotingHistory) {
			MemberVotingHistoryView(member: member)
				.environmentObject(fetch)
		}
		.sheet(isPresented: $showingComparePicker) {
			NavigationStack {
				List(pickableMembers) { other in
					Button {
						comparisonTarget = other
						showingComparePicker = false
						navigateToComparison = true
					} label: {
						HStack(spacing: 12) {
							MemberAvatar(member: other)
								.frame(width: 36, height: 36)
							VStack(alignment: .leading, spacing: 2) {
								Text(other.name).font(.headline)
								Text(other.riding).font(.caption).foregroundStyle(.secondary)
							}
						}
					}
					.foregroundStyle(.primary)
				}
				.searchable(text: $pickerSearch, prompt: "Search members")
				.navigationTitle("Compare with…")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel") { showingComparePicker = false }
					}
				}
			}
		}
	}
}

struct ProfileDetailRow: View {
	let icon: String
	let label: String
	let value: String

	var body: some View {
		HStack {
			Image(systemName: icon)
				.foregroundColor(.accentColor)
				.frame(width: 30)
			VStack(alignment: .leading) {
				Text(label)
					.font(.caption)
					.foregroundColor(.secondary)
				Text(value)
					.font(.headline)
			}
		}
	}
}

struct MemberAvatar: View {
	let member: ParliamentMember

	init(member: ParliamentMember) {
		self.member = member
	}

	var body: some View {
		AsyncImage(url: member.photoURL) { phase in
			switch phase {
			case .success(let image):
				image
					.resizable()
					.scaledToFill()
			case .failure:
				placeholder
			default:
				placeholder
			}
		}
		.clipShape(Circle())
		.overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))
	}

	private var placeholder: some View {
		ZStack {
			Color(uiColor: member.party.colour).opacity(0.2)
			Text(member.initials)
				.font(.headline)
				.foregroundColor(Color(uiColor: member.party.colour))
		}
		.background(Color(.systemGray6))
	}
}

struct PartyBadge: View {
	let party: Party

	init(party: Party) {
		self.party = party
	}

	var body: some View {
		Text(party.localizedAbbreviation)
			.font(.caption2)
			.fontWeight(.semibold)
			.foregroundColor(.white)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(Color(uiColor: party.colour))
			.clipShape(Capsule())
	}
}
