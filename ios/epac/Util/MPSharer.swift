//
//  MPSharer.swift
//  epac
//

import ActivityView
import Foundation

// Builds a share payload for an MP profile with a verified openparliament.ca link.
// openparliament.ca politician slugs are lowercase-hyphenated full names,
// e.g. "jagmeet-singh" or "pierre-poilievre".
enum MPSharer {
    static func activityItem(for member: ParliamentMember) -> ActivityItem {
        let slug = slug(for: member)
        let universalLink = URL(string: "https://openparliament.ca/politicians/\(slug)/")
            ?? URL(string: "https://openparliament.ca")!
        let text = """
\(member.name)
\(member.party.fullName) MP for \(member.riding), \(member.province.rawValue)

\(universalLink.absoluteString)
via epac — Canada's House of Commons in your pocket
"""
        return ActivityItem(items: text, universalLink)
    }

    // Converts "Jagmeet Singh" → "jagmeet-singh", handling accented characters.
    private static func slug(for member: ParliamentMember) -> String {
        let name = "\(member.firstName)-\(member.lastName)"
        return name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0 == "-" }
    }
}
