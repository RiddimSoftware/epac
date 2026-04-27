import SwiftUI

/// Compatibility wrapper for the speech feed navigation link.
///
/// The feed implementation lives in `MemberDebateActivityView`; keep this
/// name because `MemberProfileView` links to it after EPAC-299.
struct MemberSpeechFeedView: View {
    let member: ParliamentMember

    var body: some View {
        MemberDebateActivityView(member: member)
    }
}
