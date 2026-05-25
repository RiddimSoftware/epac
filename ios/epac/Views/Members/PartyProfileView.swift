//
//  PartyProfileView.swift
//  epac
//

import SwiftData
import SwiftUI

private enum PartyProfileLayout {
	static let rootSpacing: CGFloat = 20
	static let headerSpacing: CGFloat = 14
	static let partyLogoSize: CGFloat = 56
	static let logoCornerRadius = EpacCornerRadius.s
	static let cardCornerRadius = EpacCornerRadius.m
	static let compactTextSpacing = EpacSpacing.xxs
	static let seatRowSpacing: CGFloat = 12
	static let seatCountFontSize: CGFloat = 44
	static let cardTextSpacing: CGFloat = 6
	static let caucusSpacing: CGFloat = 10
	static let filterSpacing = EpacSpacing.xs
	static let memberRowSpacing: CGFloat = 10
	static let memberAvatarSize: CGFloat = 36
	static let memberTextSpacing: CGFloat = 1
	static let memberVerticalPadding = EpacSpacing.xs
}

// Party profile: aggregate view for a single Party.
//
// Seat count is computed from the ParliamentMember table, so by-elections and
// floor crossings update the number automatically once the underlying member
// data syncs. Historical seat counts and fundraising trends depend on epics
// that have not landed yet (EPAC-68 Elections Canada data, EPAC-69 fundraising
// tables) — this view shows a deferred-capability note in those slots rather
// than rendering an empty card.
struct PartyProfileView: View {
	let party: Party

	@Query(filter: #Predicate<ParliamentMember> { $0.toDateTime == nil },
	       sort: [SortDescriptor(\ParliamentMember.lastName, order: .forward)])
	private var currentMembers: [ParliamentMember]

	@State private var selectedProvince: Province?

	private var partyMembers: [ParliamentMember] {
		currentMembers.filter { $0.party == party }
	}

	private var seatCount: Int { partyMembers.count }

	private var filteredCaucus: [ParliamentMember] {
		guard let selectedProvince else { return partyMembers }
		return partyMembers.filter { $0.province == selectedProvince }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: PartyProfileLayout.rootSpacing) {
				headerCard
				seatCountCard
				historicalSeatsPlaceholder
				financingPlaceholder
				if let website = party.websiteURL {
					websiteCard(url: website)
				}
				caucusSection
			}
			.padding()
		}
		.navigationTitle(party.shortName)
		.navigationBarTitleDisplayMode(.inline)
		.accessibilityIdentifier("party-profile-scroll")
	}

	private var headerCard: some View {
		HStack(spacing: PartyProfileLayout.headerSpacing) {
			if let image = party.image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: PartyProfileLayout.partyLogoSize, height: PartyProfileLayout.partyLogoSize)
					.accessibilityHidden(true)
			} else {
				RoundedRectangle(cornerRadius: PartyProfileLayout.logoCornerRadius)
					.fill(Color(party.colour))
					.frame(width: PartyProfileLayout.partyLogoSize, height: PartyProfileLayout.partyLogoSize)
			}
			VStack(alignment: .leading, spacing: PartyProfileLayout.compactTextSpacing) {
				Text(party.fullName)
					.font(.title3.weight(.semibold))
				Text(party.localizedAbbreviation)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(PartyProfileLayout.cardCornerRadius)
	}

	private var seatCountCard: some View {
		HStack(alignment: .firstTextBaseline, spacing: PartyProfileLayout.seatRowSpacing) {
			Text("\(seatCount)")
				.font(.system(size: PartyProfileLayout.seatCountFontSize, weight: .bold, design: .rounded))
				.foregroundStyle(Color(party.colour))
			VStack(alignment: .leading, spacing: PartyProfileLayout.compactTextSpacing) {
				Text(seatCount == 1 ? "Current seat" : "Current seats")
					.font(.headline)
				Text("Calculated from current sitting MPs")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(PartyProfileLayout.cardCornerRadius)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(seatCount) current seats")
		.accessibilityIdentifier("party-profile-seat-count")
	}

	private var historicalSeatsPlaceholder: some View {
		deferredCard(
			title: "Historical seat counts",
			body: "Per-election seat totals will appear here once Elections Canada historical results land (EPAC-68)."
		)
	}

	private var financingPlaceholder: some View {
		deferredCard(
			title: "Party financing",
			body: "Annual fundraising totals and contributor counts will appear here once Elections Canada financing data lands (EPAC-69)."
		)
	}

	private func deferredCard(title: String, body: String) -> some View {
		VStack(alignment: .leading, spacing: PartyProfileLayout.cardTextSpacing) {
			Text(title)
				.font(.headline)
			Text(body)
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(PartyProfileLayout.cardCornerRadius)
	}

	private func websiteCard(url: URL) -> some View {
		VStack(alignment: .leading, spacing: PartyProfileLayout.cardTextSpacing) {
			Link(destination: url) {
				HStack {
					Label("Official party website", systemImage: "globe")
					Spacer()
					Image(systemName: "arrow.up.right.square")
						.font(.caption)
						.foregroundStyle(.tertiary)
				}
			}
			.foregroundStyle(.primary)
			Text("External link — not affiliated with epac.")
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(PartyProfileLayout.cardCornerRadius)
		.accessibilityIdentifier("party-profile-website-link")
	}

	private var caucusSection: some View {
		VStack(alignment: .leading, spacing: PartyProfileLayout.caucusSpacing) {
			HStack {
				Text("Caucus (\(seatCount))")
					.font(.headline)
				Spacer()
				Menu {
					Picker("Province", selection: $selectedProvince) {
						Text("All Provinces").tag(Province?.none)
						ForEach(provincesInCaucus, id: \.self) { province in
							Text(province.rawValue).tag(Province?.some(province))
						}
					}
				} label: {
					HStack(spacing: PartyProfileLayout.filterSpacing) {
						Image(systemName: "map")
						Text(selectedProvince?.shortCode ?? "All")
							.font(.caption)
					}
				}
				.accessibilityIdentifier("party-profile-province-filter")
			}

			if filteredCaucus.isEmpty {
				Text("No MPs in this filter.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				ForEach(filteredCaucus, id: \.id) { member in
					NavigationLink(destination: MemberProfileView(member: member)) {
						CaucusMemberRow(member: member)
					}
					.foregroundStyle(.primary)
					.accessibilityIdentifier("caucus-row-\(member.lastName.lowercased())")
				}
			}
		}
		.padding()
		.background(Color(.secondarySystemBackground))
		.cornerRadius(PartyProfileLayout.cardCornerRadius)
	}

	private var provincesInCaucus: [Province] {
		Array(Set(partyMembers.map(\.province))).sorted { $0.rawValue < $1.rawValue }
	}
}

private struct CaucusMemberRow: View {
	let member: ParliamentMember

	var body: some View {
		HStack(spacing: PartyProfileLayout.memberRowSpacing) {
			MemberAvatar(member: member)
				.frame(width: PartyProfileLayout.memberAvatarSize, height: PartyProfileLayout.memberAvatarSize)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: PartyProfileLayout.memberTextSpacing) {
				Text(member.name)
					.font(.subheadline.weight(.medium))
				Text(member.riding)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Text(member.province.shortCode)
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
			Image(systemName: "chevron.right")
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, PartyProfileLayout.memberVerticalPadding)
	}
}

// Independents are a *listing*, not a party — no leader, no website, no
// caucus aggregation that's meaningful at the party level. Surface as a
// dedicated view so callers don't have to special-case the navigation.
//
// Filtering happens in-code rather than #Predicate because SwiftData's
// predicate macro can't encode a comparison against the `Party` enum case.
struct IndependentsListingView: View {
	@Query(filter: #Predicate<ParliamentMember> { $0.toDateTime == nil },
	       sort: [SortDescriptor(\ParliamentMember.lastName)])
	private var currentMembers: [ParliamentMember]

	init() {}

	private var independents: [ParliamentMember] {
		currentMembers.filter { $0.party == .independent }
	}

	var body: some View {
		List {
			Section {
				if independents.isEmpty {
					Text("No Independent MPs are currently sitting.")
						.foregroundStyle(.secondary)
				} else {
					ForEach(independents, id: \.id) { member in
						NavigationLink(destination: MemberProfileView(member: member)) {
							CaucusMemberRow(member: member)
						}
					}
				}
			} header: {
				Text("Independent MPs (\(independents.count))")
			} footer: {
				Text("Independent is a listing, not a party — these MPs sit without caucus affiliation.")
					.font(.caption2)
			}
		}
		.navigationTitle("Independents")
		.navigationBarTitleDisplayMode(.inline)
	}
}

#Preview {
	NavigationStack {
		PartyProfileView(party: .liberal)
	}
}
