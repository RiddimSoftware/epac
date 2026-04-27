//
//  VoteSharer.swift
//  epac
//

import Foundation
import ActivityView

// Builds a share payload for a recorded vote with a verified source URL.
// The share sheet text is formatted for readability on social media and
// messaging apps; the URL links directly to the official openparliament.ca
// vote page so the recipient can verify the fact independently.
enum VoteSharer {
	static func shareItem(vote: RecordedVote, memberVote: MemberVote, member: ParliamentMember) -> ActivityItem {
		let sourceURL = url(for: vote)
		let text = shareText(vote: vote, memberVote: memberVote, member: member, sourceURL: sourceURL)
		return ActivityItem(items: text, sourceURL)
	}

	// MARK: - Private

	private static func url(for vote: RecordedVote) -> URL {
		// openparliament.ca provides clean, human-readable vote pages.
		// Format: /votes/[parliament]/[voteNumber]/
		let urlString = "https://openparliament.ca/votes/\(vote.parliament)/\(vote.number)/"
		return URL(string: urlString) ?? URL(string: "https://openparliament.ca")!
	}

	private static func shareText(
		vote: RecordedVote,
		memberVote: MemberVote,
		member: ParliamentMember,
		sourceURL: URL
	) -> String {
		let description = vote.descriptionEn.isEmpty
			? "Vote #\(vote.number)"
			: vote.descriptionEn

		let billNote = vote.billNumberCode.isEmpty ? "" : " (\(vote.billNumberCode))"
		let dateFmt = vote.date.formatted(date: .long, time: .omitted)
		let voteIcon = memberVote.recordedVote == "Yea" ? "✅"
		             : memberVote.recordedVote == "Nay" ? "❌" : "—"

		return """
\(voteIcon) \(member.name) voted \(memberVote.recordedVote) on:
\(description)\(billNote)

Result: \(vote.resultEn) · \(dateFmt)

Source: \(sourceURL.absoluteString)
via epac — Canada's House of Commons in your pocket
"""
	}
}
