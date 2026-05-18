//
//  ArtifactKeys.swift
//  epac
//

import Foundation

extension ArtifactKey {
    static let membersAll = ArtifactKey("members/v1/all.json")
    static let sittingsAll = ArtifactKey("sittings/v1/all.json")
    static let billsAll = ArtifactKey("bills/v1/all.json")
    static let calendarHouse = ArtifactKey("calendar/v1/house.ics")

    static func memberSpeeches(memberID: Int) -> ArtifactKey {
        ArtifactKey("members/v1/by-id/\(memberID)/speeches.json")
    }

    static func onThisDay(monthDay: String) -> ArtifactKey {
        ArtifactKey("on-this-day/v1/\(monthDay).json")
    }

    static func ridingBoundary(slug: String) -> ArtifactKey {
        ArtifactKey("ridings/v1/by-slug/\(slug).json")
    }

    static func sittingSpeeches(date: String) -> ArtifactKey {
        ArtifactKey("sittings/v1/by-date/\(date).json")
    }
}
