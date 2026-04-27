//
//  MemberProfileView.swift
//  epac
//
//  Created by Codex on 2026-01-28.
//

import SwiftUI
import SwiftData
import ActivityView

struct MemberProfileView: View {
	let member: ParliamentMember

	@EnvironmentObject private var fetch: Fetch
	// Compare picker only needs current MPs — predicate avoids loading all historical members.
	@Query(filter: #Predicate<ParliamentMember> { $0.toDateTime == nil },
	       sort: [SortDescriptor(\ParliamentMember.lastName)]) private var allMembers: [ParliamentMember]
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

				PartyLineScoreView(member: member)

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

				NavigationLink(destination: MemberDebateActivityView(member: member)) {
					HStack {
						Label("Debate Activity", systemImage: "text.bubble")
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
										.lineLimit(1)
									if !comm.subjectMatter.isEmpty {
										Text(comm.subjectMatter)
											.font(.caption2)
											.foregroundStyle(.secondary)
											.lineLimit(1)
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
			#if DEBUG
			Text("Member ID: \(member.memberID)")
				.font(.caption2)
				.foregroundStyle(.tertiary)
				.padding(.top, 4)
				.frame(maxWidth: .infinity)
			#endif
		}
		.padding()
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
						systemImage: followStore.isFollowing(member.memberID) ? "bell.fill" : "bell"
					)
				}
				.accessibilityLabel(
					followStore.isFollowing(member.memberID)
						? NSLocalizedString("follow.unfollow", comment: "")
						: NSLocalizedString("follow.follow", comment: "")
				)
				.accessibilityHint(
					followStore.isFollowing(member.memberID)
						? "Stops sending notifications for this member"
						: "Sends a notification when this member votes or speaks"
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
						guard let (data, _) = try? await URLSession.shared.data(from: member.photoURL),
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
