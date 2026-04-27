import SwiftUI

struct MemberSpeechFeedView: View {
	let member: ParliamentMember

	var body: some View {
		MemberDebateActivityView(member: member)
	}
}
