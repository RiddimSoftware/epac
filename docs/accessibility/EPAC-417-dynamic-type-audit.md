# EPAC-417 Dynamic Type Audit

Date: 2026-04-28

Simulator setting: Accessibility Extra Extra Extra Large (`accessibility-extra-extra-extra-large`).

## Scope

Audited the ticket's primary iOS surfaces:

- `HomeFeedView`
- `SittingView`
- `SpeechView`
- `MemberProfileView`
- `ExpendituresView`
- `BillsView`
- `BillDetailView`

## Findings And Fixes

| Surface | Finding | Fix |
| --- | --- | --- |
| Home | Live-status copy, vote/speech headlines, followed bill stages, senator caucus names, and recent debate titles used two-line caps. | Removed those caps and let source-backed text expand vertically. |
| Sitting | Oral Questions used a fixed-height internal scroll area, and topic, metadata, and excerpt text had line caps. | Removed the fixed card height and let oral-question text grow. |
| Speech | Context cards forced two or three statistic pills into one horizontal row. | Added adaptive stat rows that fall back to a vertical stack when horizontal space is tight. |
| Member profile | Lobbying organization and subject text had two-line caps; highlight stats stayed horizontal. | Let lobbying text expand and made highlights fall back to a vertical layout. |
| Expenditures | The bottom search control was overlaid on the list, and row totals/category amounts were fixed into horizontal rows. | Moved controls to a bottom safe-area inset and added vertical fallbacks for row amounts. |
| Bills list | Bill titles and current stages were capped; row metadata was forced into one horizontal line. | Let titles/stages expand and added a vertical metadata fallback. |
| Bill detail | Header badges, bill title, current stage, vote descriptions, and debate titles could truncate. | Let informational text expand and added adaptive badge layout. |

## Remaining Intentional Fixed Sizes

Fixed avatar, party-dot, disclosure, and progress indicator sizes remain. They are icons or affordances rather than informational text, and their accessibility labels are carried by the surrounding rows.

## Evidence

- Build: `xcodebuild -project ios/epac.xcodeproj -scheme epac -destination 'platform=iOS Simulator,id=FCFAF817-6694-402D-B116-A86EDAF34237' build`
- Screenshot: `docs/build-evidence/EPAC-417-running.png`
