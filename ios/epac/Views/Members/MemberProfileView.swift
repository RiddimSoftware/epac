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

	init(member: ParliamentMember) {
		self.member = member
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
			}
			.padding()
		}
		.navigationTitle(member.name)
		.navigationBarTitleDisplayMode(.large)
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
