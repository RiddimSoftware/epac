# EPAC-511 Comparison Tools Design Spec

Status: implementation reference for EPAC-511  
Sources: `docs/brand/brand-brief-v1.md`, `docs/design/design-system-v1.md`, `ios/epac/DesignSystem/*`

## Scope

This design pass defines five comparison-tool deliverables for iOS and web:

1. Comparison entry card
2. Comparison detail view
3. OG share image
4. Empty state and confidence-floor state
5. Riding history mini-component

The companion SVG comps live in `docs/design/comparison-tools/`. They are deliberately close to the SwiftUI token model so the iOS implementation can translate spacing, type, colors, and accessibility semantics without inventing a second design language.

## Token Mapping

| Design role | SwiftUI token | Notes |
| --- | --- | --- |
| Screen background | `Color.epacSurface.grouped` | Use for the comparison detail canvas. |
| Card background | `Color.epacSurface.elevated` | Entry card, breakdown sections, and riding-history panel. |
| Primary text | `Color.epacText.primary` | Entity names, score, section titles. |
| Secondary text | `Color.epacText.secondary` | Riding, source, denominator, and timestamps. |
| Action/accent | `Color.epacBrand.accent` | Compare CTA, selected filter, links. |
| Muted accent | `Color.epacBrand.accentMuted` | Score badges, filter backgrounds. |
| Positive outcome | `Color.epacBrand.positive` | Agreed-on rows and Yea indicators. |
| Negative outcome | `Color.epacBrand.negative` | Disagreed-on rows and Nay indicators. |
| Neutral state | `Color.epacBrand.neutral` | Insufficient-data and paired/abstained indicators. |

Typography maps to `Font.epacTitle`, `Font.epacHeadline`, `Font.epacSubheadline`, `Font.epacFootnote`, and `Font.epacCaption`. Spacing maps to `EpacSpacing.xs/s/m/l/xl`.

## 1. Comparison Entry Card

Files:

- `docs/design/comparison-tools/comparison-card-light.svg`
- `docs/design/comparison-tools/comparison-card-dark.svg`

Use this card on Home and My MP as the compact entry point. It should fit in a standard list/card slot and not require a hero treatment.

Layout:

- Height target: 132 pt on iPhone width.
- Outer padding: `EpacSpacing.m`.
- Horizontal structure: entity A, score badge, entity B.
- The score badge is centered and stable width so name length does not shift the layout.
- The CTA is text-only in the footer row: `Compare`.

Variants:

- MP-vs-MP: circular initials or avatar on each side, party chip below each name.
- Party-vs-party: party badge or color mark replaces avatar; copy changes from MP names to party names.

Accessibility:

- Card label: `Compare <entity A> and <entity B>`.
- Score badge label: `Similarity score <score> based on <count> common votes`.
- Do not rely on color to distinguish parties. Include party short names as text.

## 2. Comparison Detail View

Files:

- `docs/design/comparison-tools/comparison-detail-light.svg`
- `docs/design/comparison-tools/comparison-detail-dark.svg`

The detail view should answer three questions quickly:

- Who is being compared?
- How strong is the comparison?
- What evidence drives the score?

Layout:

- Navigation title: `Compare`.
- Header card: two entities, scalar score, confidence note.
- Filter pills: `All`, `Contested`, and topic filters.
- Breakdown cards: `Agreed on`, `Disagreed on`, `Recent diverging votes`.
- Topic distribution: radar chart for MP-vs-MP when topic tagging is available.
- Footer: methodology/source link.

Animation cues:

- Tapping a filter should crossfade rows in place; avoid moving the header.
- Share opens the standard share sheet from the toolbar.
- Topic radar can animate stroke trim on first appearance, but only if reduced motion is off.

Accessibility:

- Header should read as: `<entity A> compared with <entity B>. Similarity <score>. Based on <count> common votes.`
- Filter pills must expose selected state.
- Radar chart needs a text summary immediately below it, for example: `Largest overlap: housing and affordability.`
- Breakdown rows need explicit vote labels: `A voted Yea; B voted Nay`.

## 3. OG Share Image

Files:

- `website/og/compare-template.svg`
- `website/generate_compare_og.py`
- `docs/design/comparison-tools/og-share-template.png`

The OG image is 1200x630. It is built for 600x315 feed previews, so the core score and entity names stay in the central safe area.

Template fields:

- `entity_a`
- `entity_b`
- `score`
- `basis`
- `url`
- `variant`

The generator writes both SVG and PNG outputs when ImageMagick is available locally:

```bash
python3 website/generate_compare_og.py --entity-a "Leah Taylor Roy" --entity-b "Andrew Lawton" --score "68%" --basis "41 common votes" --url "epac.ca/compare/leah-taylor-roy/andrew-lawton" --output docs/design/comparison-tools/og-share-template
```

## 4. Empty And Confidence-Floor States

Files:

- `docs/design/comparison-tools/empty-confidence-states-light.svg`
- `docs/design/comparison-tools/empty-confidence-states-dark.svg`

Use two separate states:

- Empty: no common Yea/Nay votes are available.
- Confidence floor: some common votes exist, but the denominator is below the product threshold.

Copy:

- Empty title: `No common votes yet.`
- Empty body: `These records do not overlap enough to compare.`
- Confidence title: `Not enough votes for a score.`
- Confidence body: `Show the shared votes, but hold the headline score until the sample is larger.`

The copy is neutral and avoids implying a performance judgement.

## 5. Riding History Mini-Component

Files:

- `docs/design/comparison-tools/riding-history-light.svg`
- `docs/design/comparison-tools/riding-history-dark.svg`

Use this component on riding detail views, not in the comparison detail view unless the compared entities are riding-bound.

Layout:

- Vertical timeline, newest term first.
- Each term row includes member name, party chip, and date range.
- The current member uses the accent stroke; past members use neutral strokes.

Accessibility:

- Each row reads as a single sentence: `<member>, <party>, represented <riding> from <start> to <end>.`
- The current term includes `current representative`.

## Figma Handoff Notes

The SVGs are the repo-backed source artifacts for review. When moved into Figma, keep the same page structure:

- Page: `EPAC-511 Comparison Tools`
- Section: `Entry cards`
- Section: `Detail view`
- Section: `Share images`
- Section: `States`
- Section: `Riding history`

Each component should have light and dark frames side by side. Do not introduce off-system colors or type sizes while recreating these in Figma.

## Brand Review

The designs follow the brand brief by keeping the tone sourced, neutral, and civic:

- No ranking language beyond the factual score label.
- No partisan judgement copy.
- Every score surface includes denominator/confidence context.
- Methodology and source links stay visible wherever a user might infer endorsement or preference.
