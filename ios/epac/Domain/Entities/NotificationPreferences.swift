//
//  NotificationPreferences.swift
//  epac
//

import Foundation

/// In-app representation of the local user's notification preferences.
/// epac has no account system; this is a value object held by adapters that
/// persist preferences locally.
///
/// Named `NotificationPreferences` rather than `User` because the iOS chat
/// dependency `ExyteChat` exports its own `User` type and the use case sits
/// in the same module — using a domain-specific name keeps both addressable
/// from any file in the app without disambiguation.
struct NotificationPreferences: Equatable, Sendable {
    let dailyDigestOptIn: Bool
}
