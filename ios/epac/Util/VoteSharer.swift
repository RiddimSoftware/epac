//
//  VoteSharer.swift
//  epac
//

import ActivityView
import Foundation

// Builds a share payload for a recorded vote with a verified source URL.
// The share sheet text is formatted for readability on social media and
// messaging apps; the URL links directly to the official openparliament.ca
// vote page so the recipient can verify the fact independently.
enum VoteSharer {
	static func shareItem(vote: RecordedVote, memberVote: MemberVote, member: ParliamentMember) -> ActivityItem {
		let universalLink = url(for: vote)
		let text = shareText(vote: vote, memberVote: memberVote, member: member, universalLink: universalLink)
		return ActivityItem(items: text, universalLink)
	}

	// MARK: - Private

	// Universal Link: opens in epac if installed; falls back to App Store landing page.
	// The openparliament.ca URL is kept in the share text as the verifiable source.
	private static func url(for vote: RecordedVote) -> URL {
		let urlString = "https://epac.riddimsoftware.com/vote/\(vote.parliament)-\(vote.session)/\(vote.number)/"
		return URL(string: urlString) ?? URL(string: "https://epac.riddimsoftware.com")!
	}

	private static func sourceURL(for vote: RecordedVote) -> URL {
		let urlString = "https://openparliament.ca/votes/\(vote.parliament)-\(vote.session)/\(vote.number)/"
		return URL(string: urlString) ?? URL(string: "https://openparliament.ca")!
	}

	private static func shareText(
		vote: RecordedVote,
		memberVote: MemberVote,
		member: ParliamentMember,
		universalLink: URL
	) -> String {
		let description = vote.descriptionEn.isEmpty
			? "Vote #\(vote.number)"
			: vote.descriptionEn

		let billNote = vote.billNumberCode.isEmpty ? "" : " (\(vote.billNumberCode))"
		let dateFmt = vote.date.formatted(date: .long, time: .omitted)
		let voteIcon = memberVote.recordedVote == "Yea" ? "✅"
		             : memberVote.recordedVote == "Nay" ? "❌" : "—"
		let officialSource = sourceURL(for: vote).absoluteString

		return """
\(voteIcon) \(member.name) voted \(memberVote.recordedVote) on:
\(description)\(billNote)

Result: \(vote.resultEn) · \(dateFmt)

\(universalLink.absoluteString)
Official source: \(officialSource)
"""
	}
}
