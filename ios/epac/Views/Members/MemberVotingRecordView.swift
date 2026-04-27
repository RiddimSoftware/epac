//
//  MemberVotingRecordView.swift
//  epac
//

import SwiftUI
import SwiftData

struct MemberVotingRecordView: View {
	let member: ParliamentMember

	@Query private var memberVotes: [MemberVote]

	init(member: ParliamentMember) {
		self.member = member
		let memberID = member.memberID
		_memberVotes = Query(
			filter: #Predicate<MemberVote> { $0.memberID == memberID },
			sort: \.voteID, order: .reverse
		)
	}

	// MARK: - Computed stats

	private var yeaCount: Int  { memberVotes.filter { $0.recordedVote == "Yea" }.count }
	private var nayCount: Int  { memberVotes.filter { $0.recordedVote == "Nay" }.count }
	private var absentCount: Int { memberVotes.filter { $0.recordedVote == "Paired" || $0.recordedVote == "Abstained" }.count }

	/// Fraction of decisive (Yea/Nay) votes aligned with the final result.
	private var winnerAlignmentScore: Double {
		let decisive = memberVotes.filter {
			$0.vote != nil && ($0.recordedVote == "Yea" || $0.recordedVote == "Nay")
		}
		guard !decisive.isEmpty else { return 0 }
		let aligned = decisive.filter { mv in
			guard let v = mv.vote else { return false }
			return (mv.recordedVote == "Yea" && v.resultEn.localizedCaseInsensitiveContains("Agreed")) ||
			       (mv.recordedVote == "Nay" && v.resultEn.localizedCaseInsensitiveContains("Negatived"))
		}
		return Double(aligned.count) / Double(decisive.count)
	}

	var body: some View {
		Group {
			if memberVotes.isEmpty {
				ContentUnavailableView {
					Label("No voting records", systemImage: "checkmark.ballot")
				} description: {
					Text("Voting data for this member has not been loaded yet.")
				}
			} else {
				List {
					Section {
						voteSummaryCard
					}
					Section("Recent Votes") {
						ForEach(memberVotes.prefix(100)) { mv in
							VoteRow(memberVote: mv)
						}
					}
				}
				.listStyle(.insetGrouped)
			}
		}
		.navigationTitle("Voting Record")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Summary card

	private var voteSummaryCard: some View {
		VStack(spacing: 12) {
			HStack(spacing: 0) {
				SummaryPill(label: "Yea", count: yeaCount, color: .green)
				SummaryPill(label: "Nay", count: nayCount, color: .red)
				SummaryPill(label: "Absent", count: absentCount, color: .secondary)
			}
			.clipShape(RoundedRectangle(cornerRadius: 8))

			if yeaCount + nayCount > 0 {
				HStack {
					Text("Votes with the majority")
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
					Text(winnerAlignmentScore, format: .percent.precision(.fractionLength(0)))
						.font(.caption.bold())
						.foregroundStyle(winnerAlignmentScore >= 0.5 ? .green : .orange)
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

	private var voteColor: Color {
		switch memberVote.recordedVote {
		case "Yea":   return .green
		case "Nay":   return .red
		default:       return .secondary
		}
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
				if let vote = memberVote.vote {
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
		.accessibilityLabel("\(memberVote.vote?.descriptionEn ?? "Vote \(memberVote.voteID)"), \(memberVote.recordedVote)")
	}
}
