# epac Design System v1

Implements [EPAC-440](https://riddim.atlassian.net/browse/EPAC-440). All UI code from this point forward references tokens, not raw hex or literal values.

---

## Color tokens

All tokens are adaptive — light/dark is resolved by the system. Call sites never inspect `colorScheme`.

### Text (`Color.epacText`)

| Token | Usage |
|-------|-------|
| `.primary` | Primary body text, row titles |
| `.secondary` | Metadata, timestamps, descriptive labels |
| `.tertiary` | Disabled states, decorative chevrons |
| `.accent` | Linked text, highlighted labels |
| `.onAccent` | Text placed on top of an accent-coloured background |

### Surface (`Color.epacSurface`)

| Token | Usage |
|-------|-------|
| `.primary` | Screen background (`.systemBackground`) |
| `.elevated` | Cards, sheets, popovers (`.secondarySystemBackground`) |
| `.grouped` | Grouped list canvas (`.systemGroupedBackground`) |
| `.groupedElevated` | Cells inside grouped lists (`.secondarySystemGroupedBackground`) |

### Brand (`Color.epacBrand`)

| Token | Usage |
|-------|-------|
| `.accent` | Primary action tint (maps to `accentColor`) |
| `.accentMuted` | Chip backgrounds, badge fills |
| `.positive` | Yea votes, success indicators |
| `.negative` | Nay votes, destructive confirmations |
| `.neutral` | Paired/abstained votes, inactive states |

### Status (`Color.epacStatus`)

| Token | Usage |
|-------|-------|
| `.success` | Confirmation banners |
| `.warning` | Setup nudges, setup prompts (e.g. "set your postal code") |
| `.destructive` | Delete, unfollow-all actions |
| `.info` | Expenditure icons, informational content |

---

## Typography scale

All values are Dynamic Type-aware and tied to a `Font.TextStyle`. User accessibility size preferences are respected automatically.

```swift
.font(.epacDisplay)      // .largeTitle — hero numbers, dedicated-screen headers
.font(.epacTitle)        // .title — feature headlines
.font(.epacHeadline)     // .headline — section headers within a screen
.font(.epacBody)         // .body — primary body copy
.font(.epacCallout)      // .callout — list item subtitles, secondary body
.font(.epacSubheadline)  // .subheadline — row primary labels, list titles
.font(.epacFootnote)     // .footnote — fine print, source attributions
.font(.epacCaption)      // .caption — timestamps, badges, metadata
```

Weight modifiers compose normally: `.font(.epacSubheadline.weight(.semibold))`.

---

## Spacing scale

4-pt base grid. Use these constants in padding and spacing modifiers.

```swift
EpacSpacing.xs   // 4 pt — tight internal gaps (icon-to-text in a row)
EpacSpacing.s    // 8 pt — standard internal spacing
EpacSpacing.m    // 16 pt — section padding, card insets
EpacSpacing.l    // 24 pt — large gaps between sections
EpacSpacing.xl   // 32 pt — screen-level breathing room
EpacSpacing.xxl  // 48 pt — hero spacing, marketing surfaces
```

---

## Usage example

```swift
import SwiftUI

struct MyRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: EpacSpacing.s) {
            Circle()
                .fill(isActive ? Color.epacBrand.positive : Color.epacBrand.neutral)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: EpacSpacing.xs) {
                Text(title)
                    .font(.epacSubheadline.weight(.semibold))
                    .foregroundStyle(Color.epacText.primary)
                Text(subtitle)
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
            }
        }
        .padding(EpacSpacing.m)
        .background(Color.epacSurface.elevated)
    }
}
```

---

## Files

| File | Purpose |
|------|---------|
| `ios/epac/DesignSystem/EpacColor.swift` | Color token declarations |
| `ios/epac/DesignSystem/EpacFont.swift` | Typography scale |
| `ios/epac/DesignSystem/EpacSpacing.swift` | Spacing scale |
| `ios/epac/DesignSystem/DesignSystemPreviews.swift` | Snapshot-testable preview components |

Snapshot tests live in `ios/epacTests/SnapshotTests.swift` under `// MARK: - Design system tokens (EPAC-440)`.

---

## Migration guide

When updating an existing screen:

1. Replace `Color.accentColor` / `.tint` with `Color.epacBrand.accent`
2. Replace `.blue`, `.orange`, `.red` with the appropriate status or brand token
3. Replace `.font(.subheadline)` with `.font(.epacSubheadline)`, etc.
4. Replace raw padding values with `EpacSpacing.*` constants
5. Leave system semantic colors (`.primary`, `.secondary`) as-is — they are equivalent to `epacText.primary` / `epacText.secondary` and can be migrated incrementally

Two reference migrations shipped with this token set: `HomeFeedView` and `MyMPView`.
