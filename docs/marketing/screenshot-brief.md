# App Store Screenshot Production Brief

**Ticket:** EPAC-301
**Brief source:** EPAC-300 (`docs/marketing/app-store/creative-brief-epac300.md`)
**Raw captures (simulator):** `ios/fastlane/screenshots/en-US/`
**Automation:** `ios/fastlane/Snapfile`

---

## Required sizes

| Device | Resolution | Status |
|--------|------------|--------|
| iPhone 16 Pro Max (6.9") | 1320×2868px | needs compositing from raw |
| iPhone 16 (6.1") | 1179×2556px | raw captures committed (1206×2622) |
| iPad Pro 13" | 2064×2752px | out of scope until EPAC-132 |

> Note: raw captures were taken on the iPhone 16 simulator (1206×2622px). They are within the 6.1" accepted size range and can be submitted as-is or scaled up to 1320×2868 for the 6.9" slot.

---

## The 6 screenshots and their headlines

Per EPAC-300 creative brief narrative arc: _know → understand → act_

| # | Filename | Headline | Sub-caption | Screen to show |
|---|----------|----------|-------------|----------------|
| 1 | `01-parliament-in-your-pocket.png` | "Parliament voted last night." | "Find out how your MP voted — and what they said before the vote." | Voting record tab, real vote visible, MP name, Yea/Nay |
| 2 | `02-see-how-your-mp-votes.png` | "Read every word they said." | "The official Hansard transcript — in a format you can actually read." | SpeechView with debate, party colours in chat bubbles, MP names |
| 3 | `03-your-mp-everything-they-do.png` | "Everything your MP has done." | "Enter your postal code. Get your representative. See their votes, speeches, and expenses." | MyMPView with MP name, riding name, recent activity |
| 4 | `04-track-a-bill-start-to-finish.png` | "Track a bill start to finish." | "From introduction to Royal Assent — with the PBO cost estimate and every vote." | BillDetailView with stage timeline, PBO cost badge, Follow button |
| 5 | `05-know-whos-influencing-your-mp.png` | "See who voted which way." | "Every recorded division in the House of Commons, searchable by MP, party, or bill." | VoteDetailView with Yea/Nay distribution, party colour coding |
| 6 | `06-contact-them-in-one-tap.png` | "Contact them in one tap." | "Send your MP an email about any vote or debate — pre-filled from the parliamentary record." | Contact compose sheet, pre-filled subject and body referencing a real vote |

---

## Compositing instructions

For each screenshot:

1. Open raw PNG from `ios/fastlane/screenshots/en-US/` in Figma
2. Apply dark background (`#0a0a0c`)
3. Add iPhone 16 Pro Max device frame (download from [developer.apple.com/design/resources/](https://developer.apple.com/design/resources/))
4. Add headline in **Outfit ExtraBold, 42pt, white** (`#FFFFFF`)
5. Add sub-caption in **Inter Medium, 22pt, `#8a8a8e`**
6. Headline must occupy ≥30% of image height (per EPAC-300 spec)
7. Export at 1× (1320×2868px for 6.9" slot)
8. Verify headline is readable at 16% zoom (thumbnail check — 70% of App Store visitors decide from thumbnails)
9. Run through ImageOptim before upload

---

## Design tokens

| Use | Hex |
|-----|-----|
| Background | `#0a0a0c` |
| Headline | `#FFFFFF` |
| Sub-caption | `#8a8a8e` |
| Primary blue | `#0071E3` |
| Liberal red | `#D01D1D` |
| Conservative blue | `#003F7D` |
| NDP orange | `#E67E00` |
| Green | `#007D3C` |
| BQ teal | `#00A4B0` |

Party colours are WCAG AA compliant against the dark background.

---

## Automated capture (fastlane snapshot)

`ios/fastlane/Snapfile` is configured to capture both required device sizes once UI test targets are wired up. To run:

```bash
cd ios
bundle exec fastlane snapshot
```

This requires a SnapshotHelper UI test target in the `epac` scheme. Until that test target exists, use `xcrun simctl io` for manual capture (see below).

### Manual capture procedure (current method)

```bash
# 1. Build
cd ios
xcodebuild -project epac.xcodeproj -scheme epac \
  -destination 'platform=iOS Simulator,id=FCFAF817-6694-402D-B116-A86EDAF34237' build

# 2. Install
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "epac.app" \
  -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
xcrun simctl install FCFAF817-6694-402D-B116-A86EDAF34237 "$APP_PATH"

# 3. Launch and capture
xcrun simctl launch FCFAF817-6694-402D-B116-A86EDAF34237 net.dinglebox.cabinetdoor
sleep 4
xcrun simctl io FCFAF817-6694-402D-B116-A86EDAF34237 screenshot \
  "ios/fastlane/screenshots/en-US/01-parliament-in-your-pocket.png"
# ... navigate to each screen and repeat for screenshots 02–06
```

---

## Production checklist

- [ ] All screenshots show **real parliamentary data** — no placeholder names, no lorem ipsum
- [ ] iPhone 6.9" composited at 1320×2868px
- [ ] iPhone 6.1" composited at 1179×2556px (or scaled raw capture)
- [ ] Headline readable at 16% zoom on all 6 screenshots
- [ ] ImageOptim run on all exports
- [ ] Uploaded to App Store Connect (`ios/fastlane/screenshots/en-US/` → `bundle exec fastlane deliver`)
