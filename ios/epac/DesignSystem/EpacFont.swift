import SwiftUI

// 8-value typography scale. Every value maps to a Dynamic Type-aware
// system text style so accessibility size preferences are respected.

extension Font {
    // Largest — hero numbers, section headers on dedicated screens.
    static let epacDisplay: Font = .largeTitle

    // Feature headlines and screen titles.
    static let epacTitle: Font = .title

    // Section-level subheadings within a screen.
    static let epacHeadline: Font = .headline

    // Primary body copy.
    static let epacBody: Font = .body

    // Slightly smaller than body; list item subtitles.
    static let epacCallout: Font = .callout

    // Secondary labels, row detail text.
    static let epacSubheadline: Font = .subheadline

    // Fine print, source attributions.
    static let epacFootnote: Font = .footnote

    // Timestamps, badges, metadata.
    static let epacCaption: Font = .caption
}
