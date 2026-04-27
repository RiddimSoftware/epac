//
//  MemberVotingRecordView.swift
//  epac
//

import SwiftUI
import SwiftData
import ActivityView

struct MemberVotingRecordView: View {
	let member: ParliamentMember

	@Query private var memberVotes: [MemberVote]
	@State private var shareItem: ActivityItem?

	init(member: ParliamentMember) {
		self.member = member
		let memberID = member.memberID
		var descriptor = FetchDescriptor<MemberVote>(
			predicate: #Predicate<MemberVote> { $0.memberID == memberID },
			sortBy: [SortDescriptor(\.voteID, order: .reverse)]
		)
		descriptor.fetchLimit = 100
		_memberVotes = Query(descriptor)
	}

	// MARK: - Computed stats

	/// Aggregates vote tallies in a single pass to avoid repeated traversals.
	private struct VoteStats {
		var yea = 0; var nay = 0; var absent = 0
		var decisiveTotal = 0; var aligned = 0
	}

	private var voteStats: VoteStats {
		memberVotes.reduce(into: VoteStats()) { s, mv in
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

	private var yeaCount: Int    { voteStats.yea }
	private var nayCount: Int    { voteStats.nay }
	private var absentCount: Int { voteStats.absent }

	/// Fraction of decisive (Yea/Nay) votes aligned with the final result.
	private var winnerAlignmentScore: Double {
		let s = voteStats
		guard s.decisiveTotal > 0 else { return 0 }
		return Double(s.aligned) / Double(s.decisiveTotal)
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
							.padding(.vertical, 4)
					}
					Section(header: Text(NSLocalizedString("voting.recentVotes", comment: "")).accessibilityAddTraits(.isHeader)) {
						ForEach(memberVotes) { mv in
							let rv = mv.vote  // pre-resolve relationship before SwiftUI render pass
							VoteRow(memberVote: mv, rv: rv)
								.swipeActions(edge: .leading) {
									if let vote = rv {
										Button {
											let template = ContactMyMP.voteTemplate(
												vote: vote, memberVote: mv.recordedVote)
											ContactMyMP.open(to: member, template: template)
										} label: {
											Label("Write to MP", systemImage: "envelope.badge")
										}
										.tint(.blue)
									}
								}
								.swipeActions(edge: .trailing, allowsFullSwipe: false) {
									if let vote = rv {
										Button {
											shareItem = VoteSharer.shareItem(vote: vote, memberVote: mv, member: member)
										} label: {
											Label("Share", systemImage: "square.and.arrow.up")
										}
										.tint(.orange)
									}
								}
						}
					}
				}
				.listStyle(.insetGrouped)
			}
		}
		.activitySheet($shareItem)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				DataSourceBadge(source: .votes())
			}
			.padding(.horizontal)
			.padding(.vertical, 6)
		}
		.navigationTitle(NSLocalizedString("voting.title", comment: ""))
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Summary card

	private var voteSummaryCard: some View {
		VStack(spacing: 12) {
			HStack(spacing: 0) {
				SummaryPill(label: "Yea", count: yeaCount, color: .appPositive)
				SummaryPill(label: "Nay", count: nayCount, color: .appDestructive)
				SummaryPill(label: "Absent", count: absentCount, color: .secondary)
			}
			.clipShape(RoundedRectangle(cornerRadius: 8))

			if yeaCount + nayCount > 0 {
				HStack {
					Text(NSLocalizedString("voting.withMajority", comment: ""))
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
					Text(winnerAlignmentScore, format: .percent.precision(.fractionLength(0)))
						.font(.caption.bold())
						.foregroundStyle(winnerAlignmentScore >= 0.5 ? Color.appPositive : Color.appWarning)
				}
			}
		}
		.padding(.vertical, 4)
	}
}

// MARK: - Sub-views

private struct SummaryPill: View {
	let label: String
	let count: Int
	let color: Color

	var body: some View {
		VStack(spacing: 2) {
			Text("\(count)")
				.font(.title3.bold())
				.foregroundStyle(count > 0 ? color : .secondary)
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 8)
		.background(count > 0 ? color.opacity(0.08) : Color.clear)
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
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: voteIcon)
				.foregroundStyle(voteColor)
				.font(.title3)
				.frame(width: 28)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				if let vote = rv {
					Text(vote.descriptionEn.isEmpty ? "Vote #\(vote.number)" : vote.descriptionEn)
						.font(.subheadline)
						.lineLimit(2)
					HStack(spacing: 6) {
						if !vote.billNumberCode.isEmpty {
							Text(vote.billNumberCode)
								.font(.caption2)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(Color.accentColor.opacity(0.1))
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
		.padding(.vertical, 2)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(rv?.descriptionEn ?? "Vote \(memberVote.voteID)"), \(memberVote.recordedVote)")
	}
}
