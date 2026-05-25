//
//  MemberVotingRecordView.swift
//  epac
//

import ActivityView
import SwiftData
import SwiftUI

private enum MemberVotingLayout {
	static let voteFetchLimit = 100
	static let sourceBadgeVerticalPadding: CGFloat = 6
	static let summarySpacing: CGFloat = 12
	static let summaryCornerRadius = EpacCornerRadius.s
	static let majorityThreshold = EpacOpacity.overlay
	static let summaryVerticalPadding = EpacSpacing.xs
	static let pillSpacing = EpacSpacing.xxs
	static let pillVerticalPadding = EpacSpacing.s
	static let pillBackgroundOpacity = 0.08
	static let voteRowSpacing: CGFloat = 12
	static let voteIconWidth: CGFloat = 28
	static let voteTextSpacing: CGFloat = 3
	static let voteTitleLineLimit = 2
	static let voteBadgeSpacing: CGFloat = 6
	static let voteBadgeHorizontalPadding: CGFloat = 6
	static let voteBadgeVerticalPadding = EpacSpacing.xxs
	static let voteBadgeOpacity: Double = 0.1
	static let rowVerticalPadding = EpacSpacing.xxs
}

struct MemberVotingRecordView: View {
	let member: ParliamentMember

	@Environment(NavigationRouter.self) private var router
	@EnvironmentObject private var fetch: Fetch
	@Query private var memberVotes: [MemberVote]
	@State private var shareItem: ActivityItem?
	@State private var cachedStats = VoteStats()
	@State private var sortByBillNumber = false

	init(member: ParliamentMember) {
		self.member = member
		let memberID = member.memberID
		var descriptor = FetchDescriptor<MemberVote>(
			predicate: #Predicate<MemberVote> { $0.memberID == memberID },
			sortBy: [SortDescriptor(\.voteID, order: .reverse)]
		)
		descriptor.fetchLimit = MemberVotingLayout.voteFetchLimit
		_memberVotes = Query(descriptor)
	}

	// MARK: - Computed stats

	/// Aggregates vote tallies in a single pass to avoid repeated traversals.
	private struct VoteStats {
		var yea = 0; var nay = 0; var absent = 0
		var decisiveTotal = 0; var aligned = 0
	}

	// voteStats is computed once when memberVotes changes, not on every render.
	private var sortedVotes: [MemberVote] {
		if sortByBillNumber {
			return memberVotes
				.filter { !($0.vote?.billNumberCode ?? "").isEmpty }
				.sorted { ($0.vote?.billNumberCode ?? "") < ($1.vote?.billNumberCode ?? "") }
		}
		return memberVotes  // already sorted voteID desc from @Query
	}

	private var yeaCount: Int { cachedStats.yea }
	private var nayCount: Int { cachedStats.nay }
	private var absentCount: Int { cachedStats.absent }

	private var winnerAlignmentScore: Double {
		guard cachedStats.decisiveTotal > 0 else { return 0 }
		return Double(cachedStats.aligned) / Double(cachedStats.decisiveTotal)
	}

	private func recomputeStats() {
		cachedStats = memberVotes.reduce(into: VoteStats()) { s, mv in
			switch mv.recordedVote {
			case "Yea": s.yea += 1
			case "Nay": s.nay += 1
			default:    s.absent += 1
			}
			guard let v = mv.vote,
				  mv.recordedVote == "Yea" || mv.recordedVote == "Nay" else { return }
			s.decisiveTotal += 1
			let isAligned = (mv.recordedVote == "Yea" && v.resultEn.localizedCaseInsensitiveContains("Agreed")) ||
				            (mv.recordedVote == "Nay" && v.resultEn.localizedCaseInsensitiveContains("Negatived"))
			if isAligned { s.aligned += 1 }
		}
	}

	var body: some View {
		Group {
			if memberVotes.isEmpty {
				ContentUnavailableView {
					Label(NSLocalizedString("voting.empty.title", comment: ""), systemImage: "checkmark.ballot")
				} description: {
					Text(NSLocalizedString("voting.empty.description", comment: ""))
				}
			} else {
				List {
					Section {
						voteSummaryCard
					}
					Section {
						PartyLineScoreView(member: member)
							.padding(.vertical, MemberVotingLayout.summaryVerticalPadding)
					}
					Section(header: Text(NSLocalizedString("voting.recentVotes", comment: "")).accessibilityAddTraits(.isHeader)) {
						ForEach(Array(sortedVotes.enumerated()), id: \.offset) { index, mv in
							let rv = mv.vote  // pre-resolve relationship before SwiftUI render pass
							VoteRow(memberVote: mv, rv: rv)
								.accessibilityIdentifier(index == 0 ? "vote-list-row-0" : "vote-list-row-\(index)")
								.swipeActions(edge: .leading) {
									if let vote = rv {
										Button {
											let template = ContactMyMP.voteTemplate(
												vote: vote, memberVote: mv.recordedVote)
											ContactMyMP.open(to: member, template: template)
										} label: {
											Label(NSLocalizedString("vote.contextMenu.writeMP", comment: ""), systemImage: "envelope.badge")
										}
										.tint(.blue)
									}
								}
								.swipeActions(edge: .trailing, allowsFullSwipe: false) {
									if let vote = rv, !vote.billNumberCode.isEmpty {
										Button {
											router.pendingSearchQuery = vote.billNumberCode
											router.selectedTab = .search
										} label: {
											Label(NSLocalizedString("vote.contextMenu.searchDebates", comment: ""), systemImage: "magnifyingglass")
										}
										.tint(.teal)
									}
									if let vote = rv {
										Button {
											shareItem = VoteSharer.shareItem(vote: vote, memberVote: mv, member: member)
										} label: {
											Label(NSLocalizedString("vote.contextMenu.share", comment: ""), systemImage: "square.and.arrow.up")
										}
										.tint(.orange)
									}
								}
								.contextMenu {
									if let vote = rv {
										Button {
											shareItem = VoteSharer.shareItem(vote: vote, memberVote: mv, member: member)
										} label: {
											Label(NSLocalizedString("vote.contextMenu.share", comment: ""), systemImage: "square.and.arrow.up")
										}
										if !vote.billNumberCode.isEmpty {
											Button {
												router.pendingSearchQuery = vote.billNumberCode
												router.selectedTab = .search
											} label: {
												Label(NSLocalizedString("vote.contextMenu.searchDebates", comment: ""), systemImage: "magnifyingglass")
											}
										}
										Button {
											let template = ContactMyMP.voteTemplate(vote: vote, memberVote: mv.recordedVote)
											ContactMyMP.open(to: member, template: template)
										} label: {
											Label(NSLocalizedString("vote.contextMenu.writeMP", comment: ""), systemImage: "envelope")
										}
									}
								}
						}
					}
				}
				.listStyle(.insetGrouped)
				.accessibilityIdentifier("vote-detail-mp-list")
				.refreshable {
					guard member.memberID > 0 else { return }
					try? await fetch.refreshMemberVotes(memberID: member.memberID)
				}
			}
		}
		.activitySheet($shareItem)
		.onAppear { recomputeStats() }
		.onChange(of: memberVotes.count) { recomputeStats() }
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				DataSourceBadge(source: .votes())
			}
			.padding(.horizontal)
			.padding(.vertical, MemberVotingLayout.sourceBadgeVerticalPadding)
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					sortByBillNumber.toggle()
				} label: {
					Label(
						sortByBillNumber ? "Sort by Date" : "Sort by Bill",
						systemImage: sortByBillNumber ? "calendar" : "number"
					)
				}
				.accessibilityLabel(sortByBillNumber ? "Sort by date" : "Sort by bill number")
			}
		}
		.navigationTitle(NSLocalizedString("voting.title", comment: ""))
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Summary card

	private var voteSummaryCard: some View {
		VStack(spacing: MemberVotingLayout.summarySpacing) {
			HStack(spacing: 0) {
				SummaryPill(label: "Yea", count: yeaCount, color: .appPositive)
				SummaryPill(label: "Nay", count: nayCount, color: .appDestructive)
				SummaryPill(label: "Absent", count: absentCount, color: .secondary)
			}
			.clipShape(RoundedRectangle(cornerRadius: MemberVotingLayout.summaryCornerRadius))

			if yeaCount + nayCount > 0 {
				HStack {
					Text(NSLocalizedString("voting.withMajority", comment: ""))
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
					Text(winnerAlignmentScore, format: .percent.precision(.fractionLength(0)))
						.font(.caption.bold())
						.foregroundStyle(winnerAlignmentScore >= MemberVotingLayout.majorityThreshold ? Color.appPositive : Color.appWarning)
				}
			}
		}
		.padding(.vertical, MemberVotingLayout.summaryVerticalPadding)
	}
}

// MARK: - Sub-views

private struct SummaryPill: View {
	let label: String
	let count: Int
	let color: Color

	var body: some View {
		VStack(spacing: MemberVotingLayout.pillSpacing) {
			Text("\(count)")
				.font(.title3.bold())
				// `count` is an Int field on this struct, not a collection — empty_count's auto-fix is wrong here.
				// swiftlint:disable:next empty_count
				.foregroundStyle(count != 0 ? color : .secondary)
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, MemberVotingLayout.pillVerticalPadding)
		// swiftlint:disable:next empty_count
		.background(count != 0 ? color.opacity(MemberVotingLayout.pillBackgroundOpacity) : Color.clear)
	}
}

private struct VoteRow: View {
	let memberVote: MemberVote
	let rv: RecordedVote?  // pre-resolved by caller to avoid per-render relationship faults

	private var voteColor: Color {
		Color.ballot(memberVote.recordedVote)
	}

	private var voteIcon: String {
		switch memberVote.recordedVote {
		case "Yea":   return "checkmark.circle.fill"
		case "Nay":   return "xmark.circle.fill"
		default:       return "minus.circle.fill"
		}
	}

	var body: some View {
		HStack(alignment: .top, spacing: MemberVotingLayout.voteRowSpacing) {
			Image(systemName: voteIcon)
				.foregroundStyle(voteColor)
				.font(.title3)
				.frame(width: MemberVotingLayout.voteIconWidth)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: MemberVotingLayout.voteTextSpacing) {
				if let vote = rv {
					Text(vote.descriptionEn.isEmpty ? "Vote #\(vote.number)" : vote.descriptionEn)
						.font(.subheadline)
						.lineLimit(MemberVotingLayout.voteTitleLineLimit)
					HStack(spacing: MemberVotingLayout.voteBadgeSpacing) {
						if !vote.billNumberCode.isEmpty {
							Text(vote.billNumberCode)
								.font(.caption2)
								.padding(.horizontal, MemberVotingLayout.voteBadgeHorizontalPadding)
								.padding(.vertical, MemberVotingLayout.voteBadgeVerticalPadding)
								.background(Color.accentColor.opacity(MemberVotingLayout.voteBadgeOpacity))
								.foregroundStyle(Color.accentColor)
								.clipShape(Capsule())
						}
						Text(vote.date.formatted(date: .abbreviated, time: .omitted))
							.font(.caption)
							.foregroundStyle(.secondary)
						Spacer()
						Text(vote.resultEn)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				} else {
					Text("Vote #\(memberVote.voteID)")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
			}

			Text(memberVote.recordedVote)
				.font(.caption.bold())
				.foregroundStyle(voteColor)
		}
		.padding(.vertical, MemberVotingLayout.rowVerticalPadding)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(rv?.descriptionEn ?? "Vote \(memberVote.voteID)"), \(memberVote.recordedVote)")
	}
}
