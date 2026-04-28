//
//  ContactMyMP.swift
//  epac
//

import SwiftUI

// Generates pre-populated mailto: URLs so the user can write to their
// MP directly from any content screen (vote, speech, bill).
//
// "My MP" is identified by the email stored in ParliamentMember.email
// (populated by the MP contact download, EPAC-35) for the member whose
// riding matches the user's saved postal code lookup (EPAC-27).
// Falls back to a generic subject/body if no MP email is found.
enum ContactMyMP {
	struct Template {
		let subject: String
		let body: String
	}

	static func voteTemplate(vote: RecordedVote, memberVote: String?) -> Template {
		let voteDescription = vote.descriptionEn.isEmpty
			? "Vote #\(vote.number)"
			: vote.descriptionEn
		let billNote = vote.billNumberCode.isEmpty ? "" : " (\(vote.billNumberCode))"
		let result = vote.resultEn
		let myVote = memberVote.map { "Your recorded vote was: \($0)." } ?? ""

		return Template(
			subject: "Regarding \(voteDescription)\(billNote)",
			body: """
Hello,

I am writing to you as your constituent regarding the following recorded vote in the House of Commons:

\(voteDescription)\(billNote)
Result: \(result)
Date: \(vote.date.formatted(date: .long, time: .omitted))
\(myVote)

[Write your message here]

Sincerely,
[Your name]
[Your address]
"""
		)
	}

	static func billTemplate(bill: Bill) -> Template {
		let statusLine: String
		switch bill.status {
		case .royalAssent: statusLine = "Status: Received Royal Assent"
		case .defeated:    statusLine = "Status: Defeated"
		case .inProgress:  statusLine = "Status: \(bill.currentStage)"
		case .unknown:     statusLine = "Status: \(bill.currentStage)"
		}
		return Template(
			subject: "Regarding \(bill.number): \(bill.title)",
			body: """
Hello,

I am writing to you as your constituent regarding the following bill currently before Parliament:

\(bill.number): \(bill.title)
Sponsored by: \(bill.sponsorName)
\(statusLine)

[Write your message here]

Sincerely,
[Your name]
[Your address]
"""
		)
	}

	static func speechTemplate(subjectTitle: String, speakerName: String, date: Date) -> Template {
		Template(
			subject: "Regarding the debate on \(subjectTitle)",
			body: """
Hello,

I am writing as your constituent regarding the following debate in the House of Commons:

Subject: \(subjectTitle)
Speaker: \(speakerName)
Date: \(date.formatted(date: .long, time: .omitted))

[Write your message here]

Sincerely,
[Your name]
[Your address]
"""
		)
	}

	/// Builds and opens a mailto: URL. Falls back to the member's
	/// profile email if present, otherwise opens Mail with no recipient.
	@MainActor
	static func open(to member: ParliamentMember?, template: Template) {
		let email = member?.email ?? ""
		var components = URLComponents()
		components.scheme = "mailto"
		components.path = email
		components.queryItems = [
			URLQueryItem(name: "subject", value: template.subject),
			URLQueryItem(name: "body", value: template.body)
		]
		guard let url = components.url else { return }
		UIApplication.shared.open(url)
		HapticEngine.medium()
		ReviewRequestManager.shared.requestReviewIfAppropriate()
	}
}

// MARK: - SwiftUI button

struct ContactMyMPButton: View {
	let myMP: ParliamentMember?
	let template: ContactMyMP.Template

	var body: some View {
		Button {
			ContactMyMP.open(to: myMP, template: template)
		} label: {
			Label(NSLocalizedString("contact.writeToMP", comment: ""), systemImage: "envelope.badge")
		}
		.accessibilityHint("Opens Mail with a pre-filled message to your Member of Parliament")
		.accessibilityIdentifier("mp-profile-contact-button")
	}
}
