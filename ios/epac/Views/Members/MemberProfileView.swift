//
//  MemberProfileView.swift
//  epac
//
//  Created by Codex on 2026-01-28.
//

import ActivityView
import AppIntents
import SwiftData
import SwiftUI

struct MemberProfileView: View {
	let member: ParliamentMember

	@EnvironmentObject private var fetch: Fetch
	// Compare picker only needs current MPs — predicate avoids loading all historical members.
	@Query(filter: #Predicate<ParliamentMember> { $0.toDateTime == nil },
	       sort: [SortDescriptor(\ParliamentMember.lastName)]) private var allMembers: [ParliamentMember]
	@Query private var cabinetPositions: [CabinetPosition]

	private var cabinetPosition: CabinetPosition? {
		// Match on (firstName, lastName) — matching on lastName alone would
		// surface a Cabinet section on every MP sharing a surname with a
		// minister (e.g. Thompson, Sidhu, MacDonald, Miller).
		let memberKey = CabinetMatch.key(firstName: member.firstName, lastName: member.lastName)
		return cabinetPositions.first { CabinetMatch.key(firstName: $0.firstName, lastName: $0.lastName) == memberKey }
	}
	@State private var showingComparePicker = false
	@State private var comparisonTarget: ParliamentMember?
	@State private var navigateToComparison = false
	@State private var pickerSearch = ""
	@State private var showVotingHistory = false
	@State private var followStore = MemberFollowStore.shared
	@State private var showLobbying = false
	@State private var lobbyingComms: [LobbyistCommunication] = []
	@State private var showCopiedConfirmation = false
	@State private var lobbyingLoaded = false
	@State private var showEthics = false
	@State private var shareItem: ActivityItem?

	init(member: ParliamentMember) {
		self.member = member
	}

	private var contactSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let email = member.email, let url = URL(string: "mailto:\(email)") {
				HStack(spacing: 0) {
					Button { UIApplication.shared.open(url) } label: {
						ProfileDetailRow(icon: "envelope.fill", label: NSLocalizedString("contact.email", comment: ""), value: email)
					}
					.foregroundStyle(.primary)
					.accessibilityIdentifier("mp-profile-contact-button")
					Button {
						UIPasteboard.general.string = email
						showCopiedConfirmation = true
						Task {
							try? await Task.sleep(nanoseconds: 1_500_000_000)
							showCopiedConfirmation = false
						}
					} label: {
						ZStack {
							Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
								.font(.caption)
								.foregroundStyle(showCopiedConfirmation ? Color.appPositive : Color.secondary)
								.padding(.horizontal, 8)
						}
					}
					.accessibilityLabel(showCopiedConfirmation ? "Copied" : "Copy email address")
					.accessibilityHint("Copies \(email) to clipboard")
				}
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

	@ViewBuilder
	private func partyDestination(for party: Party) -> some View {
		if party == .independent {
			IndependentsListingView()
		} else {
			PartyProfileView(party: party)
		}
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

				MemberHighlightsCard(member: member)

				PartyLineScoreView(member: member)

				VStack(alignment: .leading, spacing: 10) {
					NavigationLink(destination: partyDestination(for: member.party)) {
						HStack(spacing: 0) {
							ProfileDetailRow(icon: "flag.fill", label: "Party", value: member.party.fullName)
							Image(systemName: "chevron.right")
								.font(.caption)
								.foregroundStyle(.tertiary)
						}
					}
					.foregroundStyle(.primary)
					.accessibilityIdentifier("mp-profile-party-link")
					ProfileDetailRow(icon: "mappin.and.ellipse", label: "Riding", value: member.riding)
					ProfileDetailRow(icon: "location.fill", label: "Province", value: member.province.rawValue)
				}
				.padding()
				.background(Color(.secondarySystemBackground))
				.cornerRadius(12)

				RidingBoundaryMapCard(ridingName: member.riding, party: member.party)
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)

				if let position = cabinetPosition {
					CabinetPositionSection(position: position)
				}

				if member.email != nil || member.hillPhone != nil || member.constituencyPhone != nil || member.constituencyAddress != nil {
					contactSection
				} else if !member.contactFetched {
					HStack(spacing: 8) {
						ProgressView().scaleEffect(0.8)
						Text(NSLocalizedString("member.contact.loading", comment: ""))
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					.padding()
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)
				}

				NavigationLink(destination: MemberVotingRecordView(member: member)) {
					HStack {
						Label(NSLocalizedString("voting.title", comment: ""), systemImage: "checkmark.ballot")
						Spacer()
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)
				}
				.foregroundStyle(.primary)

				NavigationLink(destination: RidingElectionHistoryView(member: member)) {
					HStack {
						Label("Riding History", systemImage: "chart.bar.xaxis.ascending")
						Spacer()
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)
				}
				.foregroundStyle(.primary)

				// MARK: Lobbying section
				DisclosureGroup(
					isExpanded: $showLobbying,
					content: {
						if lobbyingComms.isEmpty && lobbyingLoaded {
							Text(NSLocalizedString("lobbying.empty.title", comment: ""))
								.font(.caption)
								.foregroundStyle(.secondary)
								.padding(.vertical, 8)
						} else {
							ForEach(lobbyingComms.prefix(3)) { comm in
								VStack(alignment: .leading, spacing: 3) {
									Text(comm.organizationName)
										.font(.subheadline)
										.fixedSize(horizontal: false, vertical: true)
									if !comm.subjectMatter.isEmpty {
										Text(comm.subjectMatter)
											.font(.caption2)
											.foregroundStyle(.secondary)
											.fixedSize(horizontal: false, vertical: true)
									}
									if let d = comm.communicationDate {
										Text(d, style: .date)
											.font(.caption2)
											.foregroundStyle(.secondary)
									}
								}
								.padding(.vertical, 2)
							}
							if !lobbyingComms.isEmpty {
								NavigationLink(destination: LobbyingView(member: member)) {
									Text(String(format: NSLocalizedString("lobbying.seeAll", comment: ""), lobbyingComms.count))
										.font(.caption)
										.foregroundStyle(.tint)
								}
								.accessibilityIdentifier("accountability-lobbying-link")
							}
						}
					},
					label: {
						HStack {
							Image(systemName: "person.fill.badge.plus")
								.foregroundStyle(.tint)
							Text(NSLocalizedString("lobbying.sectionTitle", comment: ""))
								.font(.subheadline)
								.fontWeight(.semibold)
						}
					}
				)
				.padding()
				.background(Color.appSurface)
				.cornerRadius(12)
				.onChange(of: showLobbying) { _, isExpanded in
					if isExpanded && !lobbyingLoaded {
						// Capture primitive name values on the main actor before async hop.
						let ln = member.lastName
						let fn = member.firstName
						Task {
							lobbyingComms = await LobbyistService.fetchCommunications(lastName: ln, firstName: fn)
							lobbyingLoaded = true
						}
					}
				}
			}

			// MARK: Ethics disclosures
			let ethicsInvestigations = EthicsInvestigationsDatabase.investigations(for: member.lastName)
			DisclosureGroup(
				isExpanded: $showEthics,
				content: {
					if ethicsInvestigations.isEmpty {
						VStack(alignment: .leading, spacing: 6) {
							Text("No Commissioner reports found for this MP.")
								.font(.caption)
								.foregroundStyle(.secondary)
								.padding(.vertical, 4)
							Link("View annual compliance status (CIEC)", destination: EthicsInvestigationsDatabase.complianceStatusURL)
								.font(.caption)
							Link("Public registry — disclosures and statements", destination: EthicsInvestigationsDatabase.registryURL)
								.font(.caption)
						}
					} else {
						ForEach(ethicsInvestigations) { investigation in
							VStack(alignment: .leading, spacing: 3) {
								Text(investigation.reportTitle)
									.font(.subheadline)
								Text("\(investigation.type) · \(EthicsInvestigationsDatabase.formattedDate(investigation.date))")
									.font(.caption2)
									.foregroundStyle(.secondary)
								Link("Read report →", destination: investigation.pageURL)
									.font(.caption2)
									.foregroundStyle(.tint)
							}
							.padding(.vertical, 2)
						}
						Link("All Commissioner reports", destination: EthicsInvestigationsDatabase.commissionerURL)
							.font(.caption)
							.foregroundStyle(.tint)
					}
				},
				label: {
					HStack {
						Image(systemName: "checkmark.shield.fill")
							.foregroundStyle(.tint)
						Text("Ethics Disclosures")
							.font(.subheadline)
							.fontWeight(.semibold)
					}
				}
			)
			.padding()
			.background(Color.appSurface)
			.cornerRadius(12)

			// MARK: Written Questions
			WrittenQuestionsSection(member: member)

			// Siri shortcut tip — lets users add "Open MP profile in epac" to Shortcuts
			ShortcutsLink()
				.shortcutsLinkStyle(.automaticOutline)
				.padding(.top, 4)
				.accessibilityLabel("Add epac to Siri and Shortcuts")

			#if DEBUG
			Text("Member ID: \(member.memberID)")
				.font(.caption2)
				.foregroundStyle(.tertiary)
				.padding(.top, 4)
				.frame(maxWidth: .infinity)
			#endif
		}
		.accessibilityIdentifier("mp-profile-scroll")
		.padding()
		.animation(.none, value: showLobbying)
		.animation(.none, value: showEthics)
		.task(id: member.memberID) {
			try? await fetch.downloadMemberContact(identifier: member.persistentModelID)
			if member.memberID > 0 {
				try? await fetch.downloadWrittenQuestions(memberID: member.memberID)
			}
		}
		.onAppear {
			if followStore.isFollowing(member.memberID) {
				ReviewRequestManager.shared.recordFollowedMemberProfileView(memberID: member.memberID)
			}
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
					shareItem = MPSharer.activityItem(for: member)
				} label: {
					Label(NSLocalizedString("member.share", comment: ""), systemImage: "square.and.arrow.up")
				}
				.accessibilityLabel(NSLocalizedString("member.share", comment: ""))
				.accessibilityHint("Opens the share sheet")
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					pickerSearch = ""
					showingComparePicker = true
				} label: {
					Label("Compare", systemImage: "person.2.badge.gearshape")
				}
				.accessibilityLabel("Compare with another member")
				.accessibilityHint("Opens a picker to select another member for comparison")
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					followStore.toggle(member.memberID)
					HapticEngine.light()
				} label: {
					Label(
						followStore.isFollowing(member.memberID)
							? NSLocalizedString("follow.unfollow", comment: "")
							: NSLocalizedString("follow.follow", comment: ""),
						systemImage: followStore.isFollowing(member.memberID) ? "star.fill" : "star"
					)
				}
				.accessibilityLabel(
					followStore.isFollowing(member.memberID)
						? NSLocalizedString("follow.unfollow", comment: "")
						: NSLocalizedString("follow.follow", comment: "")
				)
				.accessibilityHint(
					followStore.isFollowing(member.memberID)
						? "Removes this member from followed MPs"
						: "Adds this member to followed MPs"
				)
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
		.activitySheet($shareItem)
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

// MARK: - Member highlights

struct MemberHighlightsCard: View {
    let member: ParliamentMember
    @Query private var memberVotes: [MemberVote]

    init(member: ParliamentMember) {
        self.member = member
        let mid = member.memberID
        _memberVotes = Query(FetchDescriptor<MemberVote>(predicate: #Predicate { $0.memberID == mid }))
    }

    var body: some View {
        statCell(icon: "hand.raised.fill", value: "\(memberVotes.count)", label: NSLocalizedString("votes.navTitle", comment: ""))
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(Color.party(member.party))
                .accessibilityHidden(true)
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
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
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

struct MemberAvatar: View {
	let member: ParliamentMember
	@State private var cachedImage: UIImage?

	init(member: ParliamentMember) {
		self.member = member
	}

	var body: some View {
		Group {
			if let image = cachedImage {
				Image(uiImage: image).resizable().scaledToFill()
					.accessibilityLabel(member.name)
			} else {
				placeholder
					.accessibilityHidden(true)  // parent row composes the full label
					.task(id: member.memberID) {
						// NSCache fast path (populated by SpeakerImageViewModel or a prior cell)
						if let cached = MemberImageCache.shared.image(for: member.photoURL) {
							cachedImage = cached
							return
						}
						// SwiftData persistent cache: decode JPEG off the main thread so body
						// evaluation stays fast during list scrolling (~3 ms per decode × 15
						// visible rows = 45 ms saved per frame at 60 fps).
						if let data = member.imageData {
							let img = await Task.detached(priority: .utility) {
								UIImage(data: data)
							}.value
							if let img {
								MemberImageCache.shared.store(img, for: member.photoURL)
								cachedImage = img
								return
							}
						}
						// Network fetch fallback
						guard let (data, _) = try? await NetworkService.shared.data(from: member.photoURL),
						      let img = UIImage(data: data) else { return }
						MemberImageCache.shared.store(img, for: member.photoURL)
						cachedImage = img
					}
			}
		}
		.clipShape(Circle())
		.overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))
	}

	private var placeholder: some View {
		ZStack {
			Color.party(member.party).opacity(0.2)
			Text(member.initials)
				.font(.headline)
				.foregroundColor(Color.party(member.party))
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
			.background(Color.party(party))
			.clipShape(Capsule())
			.accessibilityLabel(party.fullName)
	}
}

struct CabinetPositionSection: View {
	let position: CabinetPosition

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 6) {
				Image(systemName: "building.columns.fill")
					.foregroundStyle(Color.accentColor)
				Text(position.isPrimeMinister ? "Prime Minister" : "Cabinet Minister")
					.font(.headline)
				Spacer()
			}

			Text(position.portfolio)
				.font(.subheadline)
				.foregroundStyle(.primary)
				.fixedSize(horizontal: false, vertical: true)

			if let urlString = position.mandateLetterURL, let url = URL(string: urlString) {
				Link(destination: url) {
					HStack {
						Label("Mandate letter", systemImage: "doc.text.fill")
						Spacer()
						Image(systemName: "arrow.up.right.square")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
				.foregroundStyle(.primary)
			} else {
				Text("No mandate letter has been published for this portfolio yet.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			HStack(spacing: 4) {
				Text("Source:")
				if let sourceURL = URL(string: position.sourceURL) {
					Link(position.sourceTitle, destination: sourceURL)
				} else {
					Text(position.sourceTitle)
				}
			}
			.font(.caption2)
			.foregroundStyle(.secondary)
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(12)
		.accessibilityElement(children: .combine)
		.accessibilityIdentifier("cabinet-position-section")
		.accessibilityLabel("\(position.isPrimeMinister ? "Prime Minister" : "Cabinet Minister"). Portfolio: \(position.portfolio)")
	}
}
