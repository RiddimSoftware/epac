//
//  SnippetParser.swift
//  epac
//

import Foundation

struct SnippetParser {
    static func parse(_ html: String) -> AttributedString {
        var result = AttributedString()
        var remaining = html[...]

        while !remaining.isEmpty {
            if let markStart = remaining.range(of: "<mark>") {
                let leadingText = remaining[..<markStart.lowerBound]
                if !leadingText.isEmpty {
                    result.append(AttributedString(String(leadingText)))
                }
                remaining = remaining[markStart.upperBound...]

                if let markEnd = remaining.range(of: "</mark>") {
                    let highlightedText = String(remaining[..<markEnd.lowerBound])
                    var highlighted = AttributedString(highlightedText)
                    highlighted.inlinePresentationIntent = .emphasized
                    result.append(highlighted)
                    remaining = remaining[markEnd.upperBound...]
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            } else {
                result.append(AttributedString(String(remaining)))
                break
            }
        }

        return result
    }
}
