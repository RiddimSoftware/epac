//
//  SpotlightIndexer.swift
//  epac
//

import CoreSpotlight
import UIKit

// Indexes parliamentary data into CoreSpotlight for system-wide search.
// Deep-link format: net.dinglebox.cabinetdoor.member.<memberID>
//
// Callers snapshot @Model data into MemberEntry (a plain Sendable struct)
// on @MainActor before passing to the indexing functions, which avoids
// Swift 6 actor-isolation errors from sending @MainActor-bound model objects
// across concurrency boundaries.
enum SpotlightIndexer {
    static let memberDomain = "net.dinglebox.cabinetdoor.member"

    struct MemberEntry: Sendable {
        let memberID: Int
        let name: String
        let firstName: String
        let lastName: String
        let riding: String
        let partyFullName: String
        let partyAbbrev: String
        let province: String
        // imageData intentionally excluded: loading photo data for 338 members on the
        // main thread (required for @MainActor makeEntries) caused a multi-second stall
        // that delayed keyboard appearance. Spotlight thumbnails are optional cosmetic.
    }

    // Called after @Query members are available on the main actor.
    // Snapshot here, then index on any actor.
    @MainActor
    static func makeEntries(from members: [ParliamentMember]) -> [MemberEntry] {
        members.map {
            MemberEntry(
                memberID: $0.memberID,
                name: $0.name,
                firstName: $0.firstName,
                lastName: $0.lastName,
                riding: $0.riding,
                partyFullName: $0.party.fullName,
                partyAbbrev: $0.party.abbreviation,
                province: $0.province.rawValue
            )
        }
    }

    static func indexMembers(_ entries: [MemberEntry]) async {
        guard !entries.isEmpty else { return }
        let items: [CSSearchableItem] = entries.map { e in
            let attrs = CSSearchableItemAttributeSet(contentType: .contact)
            attrs.displayName = e.name
            attrs.contentDescription = "\(e.partyFullName) · \(e.riding)"
            attrs.keywords = [e.name, e.firstName, e.lastName, e.riding,
                              e.partyFullName, e.partyAbbrev, e.province]
            return CSSearchableItem(
                uniqueIdentifier: "\(memberDomain).\(e.memberID)",
                domainIdentifier: memberDomain,
                attributeSet: attrs
            )
        }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    // Parses a Spotlight uniqueIdentifier back to a memberID for deep-link navigation.
    static func memberID(from activityIdentifier: String) -> Int? {
        guard activityIdentifier.hasPrefix("\(memberDomain)."),
              let idStr = activityIdentifier.split(separator: ".").last,
              let id = Int(idStr) else { return nil }
        return id
    }
}
