import Foundation
import Observation
import UserNotifications

// Global on/off switches for each notification category. Per-member sub-preferences
// (votes/speeches) remain in MemberFollowStore. Schedulers check both the global
// switch here and the per-member preference before firing.
@MainActor
@Observable
final class NotificationPreferenceStore {
    static let shared = NotificationPreferenceStore()

    // MARK: - System permission (read-only, refreshed on demand)

    private(set) var systemAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    func refreshSystemPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemAuthorizationStatus = settings.authorizationStatus
    }

    // MARK: - Activity

    var followedMPVotes: Bool = true {
        didSet {
            UserDefaults.standard.set(followedMPVotes, forKey: Keys.followedMPVotes)
            Log.info("notification.pref.changed category=followedMPVotes enabled=\(followedMPVotes)")
        }
    }
    var followedMPSpeeches: Bool = true {
        didSet {
            UserDefaults.standard.set(followedMPSpeeches, forKey: Keys.followedMPSpeeches)
            Log.info("notification.pref.changed category=followedMPSpeeches enabled=\(followedMPSpeeches)")
        }
    }
    var followedBillStatusChanges: Bool = true {
        didSet {
            UserDefaults.standard.set(followedBillStatusChanges, forKey: Keys.followedBillStatusChanges)
            Log.info("notification.pref.changed category=followedBillStatusChanges enabled=\(followedBillStatusChanges)")
        }
    }
    var followedTopicAlerts: Bool = true {
        didSet {
            UserDefaults.standard.set(followedTopicAlerts, forKey: Keys.followedTopicAlerts)
            Log.info("notification.pref.changed category=followedTopicAlerts enabled=\(followedTopicAlerts)")
        }
    }

    // MARK: - Digests

    var dailyDigest: Bool = false {
        didSet {
            UserDefaults.standard.set(dailyDigest, forKey: Keys.dailyDigest)
            Log.info("notification.pref.changed category=dailyDigest enabled=\(dailyDigest)")
        }
    }
    var fridayWeeklyDigest: Bool = false {
        didSet {
            UserDefaults.standard.set(fridayWeeklyDigest, forKey: Keys.fridayWeeklyDigest)
            Log.info("notification.pref.changed category=fridayWeeklyDigest enabled=\(fridayWeeklyDigest)")
        }
    }

    // MARK: - Government updates

    var newHansardSittings: Bool = true {
        didSet {
            UserDefaults.standard.set(newHansardSittings, forKey: Keys.hansard)
            Log.info("notification.pref.changed category=newHansardSittings enabled=\(newHansardSittings)")
        }
    }
    var pboCosting: Bool = true {
        didSet {
            UserDefaults.standard.set(pboCosting, forKey: Keys.pboCosting)
            Log.info("notification.pref.changed category=pboCosting enabled=\(pboCosting)")
        }
    }
    var lobbyingAlerts: Bool = false {
        didSet {
            UserDefaults.standard.set(lobbyingAlerts, forKey: Keys.lobbyingAlerts)
            Log.info("notification.pref.changed category=lobbyingAlerts enabled=\(lobbyingAlerts)")
        }
    }

    // MARK: - General

    var appAnnouncements: Bool = true {
        didSet {
            UserDefaults.standard.set(appAnnouncements, forKey: Keys.appAnnouncements)
            Log.info("notification.pref.changed category=appAnnouncements enabled=\(appAnnouncements)")
        }
    }

    // MARK: - Legacy (kept for scheduler backwards compat, not shown in new UI)

    // These were the original five; schedulers still gate on them.
    // New schedulers should gate on the new granular keys above.
    var memberActivity: Bool {
        get { followedMPVotes || followedMPSpeeches }
        set {
            followedMPVotes = newValue
            followedMPSpeeches = newValue
        }
    }
    var billVoteResults: Bool {
        get { followedBillStatusChanges }
        set { followedBillStatusChanges = newValue }
    }
    var topicConsultations: Bool {
        get { followedTopicAlerts }
        set { followedTopicAlerts = newValue }
    }
    var morningBriefing: Bool {
        get { dailyDigest }
        set { dailyDigest = newValue }
    }

    // MARK: - Keys

    private enum Keys {
        static let hansard                  = "epac.notifications.hansard"
        // Legacy (kept for read-back on first launch)
        static let billVotes                = "epac.notifications.billVotes"
        static let memberActivity           = "epac.notifications.memberActivity"
        static let topicConsultations       = "epac.notifications.topicConsultations"
        static let morningBriefing          = "epac.notifications.morningBriefing"
        // New granular keys
        static let followedMPVotes          = "epac.notifications.followedMPVotes"
        static let followedMPSpeeches       = "epac.notifications.followedMPSpeeches"
        static let followedBillStatusChanges = "epac.notifications.followedBillStatusChanges"
        static let followedTopicAlerts      = "epac.notifications.followedTopicAlerts"
        static let dailyDigest              = "epac.notifications.dailyDigest"
        static let fridayWeeklyDigest       = "epac.notifications.fridayWeeklyDigest"
        static let pboCosting               = "epac.notifications.pboCosting"
        static let lobbyingAlerts           = "epac.notifications.lobbyingAlerts"
        static let appAnnouncements         = "epac.notifications.appAnnouncements"
    }

    private init() {
        let d = UserDefaults.standard

        // Migrate legacy memberActivity → new granular keys if no new keys stored yet.
        let legacyMemberActivity: Bool? = d.object(forKey: Keys.memberActivity) != nil
            ? d.bool(forKey: Keys.memberActivity) : nil

        if d.object(forKey: Keys.hansard)            != nil { newHansardSittings      = d.bool(forKey: Keys.hansard) }
        if d.object(forKey: Keys.followedMPVotes)    != nil { followedMPVotes         = d.bool(forKey: Keys.followedMPVotes) }
        else if let legacy = legacyMemberActivity    { followedMPVotes                = legacy }
        if d.object(forKey: Keys.followedMPSpeeches) != nil { followedMPSpeeches      = d.bool(forKey: Keys.followedMPSpeeches) }
        else if let legacy = legacyMemberActivity    { followedMPSpeeches             = legacy }

        if d.object(forKey: Keys.followedBillStatusChanges) != nil {
            followedBillStatusChanges = d.bool(forKey: Keys.followedBillStatusChanges)
        } else if d.object(forKey: Keys.billVotes) != nil {
            followedBillStatusChanges = d.bool(forKey: Keys.billVotes)
        }

        if d.object(forKey: Keys.followedTopicAlerts) != nil {
            followedTopicAlerts = d.bool(forKey: Keys.followedTopicAlerts)
        } else if d.object(forKey: Keys.topicConsultations) != nil {
            followedTopicAlerts = d.bool(forKey: Keys.topicConsultations)
        }

        if d.object(forKey: Keys.dailyDigest)          != nil { dailyDigest          = d.bool(forKey: Keys.dailyDigest) }
        else if d.object(forKey: Keys.morningBriefing) != nil { dailyDigest          = d.bool(forKey: Keys.morningBriefing) }
        if d.object(forKey: Keys.fridayWeeklyDigest)   != nil { fridayWeeklyDigest   = d.bool(forKey: Keys.fridayWeeklyDigest) }
        if d.object(forKey: Keys.pboCosting)           != nil { pboCosting           = d.bool(forKey: Keys.pboCosting) }
        if d.object(forKey: Keys.lobbyingAlerts)       != nil { lobbyingAlerts       = d.bool(forKey: Keys.lobbyingAlerts) }
        if d.object(forKey: Keys.appAnnouncements)     != nil { appAnnouncements     = d.bool(forKey: Keys.appAnnouncements) }
    }
}
