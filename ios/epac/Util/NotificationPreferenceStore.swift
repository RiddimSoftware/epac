import Foundation
import Observation

// Global on/off switches for each notification category. Per-member sub-preferences
// (votes/speeches/expenses) remain in MemberFollowStore. The schedulers check both
// the global switch here and the per-member preference before firing.
@MainActor
@Observable
final class NotificationPreferenceStore {
    static let shared = NotificationPreferenceStore()

    var newHansardSittings: Bool = true {
        didSet { UserDefaults.standard.set(newHansardSittings, forKey: Keys.hansard) }
    }
    var billVoteResults: Bool = true {
        didSet { UserDefaults.standard.set(billVoteResults, forKey: Keys.billVotes) }
    }
    var memberActivity: Bool = true {
        didSet { UserDefaults.standard.set(memberActivity, forKey: Keys.memberActivity) }
    }
    var topicConsultations: Bool = true {
        didSet { UserDefaults.standard.set(topicConsultations, forKey: Keys.topicConsultations) }
    }
    var morningBriefing: Bool = false {
        didSet { UserDefaults.standard.set(morningBriefing, forKey: Keys.morningBriefing) }
    }

    private enum Keys {
        static let hansard            = "epac.notifications.hansard"
        static let billVotes          = "epac.notifications.billVotes"
        static let memberActivity     = "epac.notifications.memberActivity"
        static let topicConsultations = "epac.notifications.topicConsultations"
        static let morningBriefing    = "epac.notifications.morningBriefing"
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.hansard)            != nil { newHansardSittings  = d.bool(forKey: Keys.hansard) }
        if d.object(forKey: Keys.billVotes)          != nil { billVoteResults     = d.bool(forKey: Keys.billVotes) }
        if d.object(forKey: Keys.memberActivity)     != nil { memberActivity      = d.bool(forKey: Keys.memberActivity) }
        if d.object(forKey: Keys.topicConsultations) != nil { topicConsultations  = d.bool(forKey: Keys.topicConsultations) }
        if d.object(forKey: Keys.morningBriefing)    != nil { morningBriefing     = d.bool(forKey: Keys.morningBriefing) }
    }
}
