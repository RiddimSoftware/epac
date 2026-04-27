# Bill Page UX Spec (EPAC-454)

## Why

The bill page should answer one question quickly: "What is this bill, where is it in Parliament, and what can I do next?" The current implementation has the right foundations: LEGISinfo-backed metadata, a stage timeline, vote and debate cross-references, following, sharing, Contact My MP, and PBO costing when available. This spec defines the next version so follow-up implementation tickets can be small and reviewable.

## Source Rules

All bill content must trace to authoritative sources:

- Parliament of Canada LEGISinfo for bill number, title, sponsor, type, chamber, status, stages, dates, and official links.
- Parliament of Canada recorded votes for bill-related votes.
- House of Commons Hansard for debate excerpts and debate navigation.
- Parliamentary Budget Officer for independent costing notes.
- Local user state only for follow/followed status and My MP contact affordances.

Do not generate bill summaries, implications, topic labels, or "plain language" explanations without a source-backed content pipeline and human-reviewed taxonomy. Explanatory UI can define parliamentary terms such as "second reading" or "Royal Assent" from static app copy.

## Primary User Jobs

- Check status: see whether the bill is in progress, passed, defeated, or at Royal Assent.
- Understand progress: see the completed and next parliamentary stages without reading the full LEGISinfo page.
- Inspect accountability: find votes, debates, sponsor, costing notes, and official source links.
- Act: follow the bill, share it, search related activity, or write to the user's MP.

## Page Structure

### 1. Header Summary

Purpose: make the bill identifiable before the user scrolls.

Content:

- Bill number, using monospaced digits for scanability.
- Short title or official long title.
- Status badge using the existing `BillStatus` palette.
- Type badge: Government, PMB, or Senate.
- Parliament/session label.
- Last known stage.

Behavior:

- Title wraps to three lines before truncation.
- Status and type badges never carry the only accessible meaning; the row or header must expose a combined VoiceOver label.
- If title is missing, fall back to bill number and source link rather than inventing copy.

### 2. Key Facts

Purpose: provide the bill metadata a user expects before chronology.

Rows:

- Sponsor.
- Originating chamber.
- Introduced date.
- Current stage.
- Official LEGISinfo link.
- PBO costing availability when present.

Sponsor behavior:

- If the sponsor resolves to a `ParliamentMember`, show party badge and link to the member profile.
- If resolution fails, show the official sponsor name as plain source text.

### 3. Stage Timeline

Purpose: show progress through Parliament in reading order.

Requirements:

- House-originating bills: House first, second, committee/report where available, third, Senate first, second, committee/report where available, third, Royal Assent.
- Senate-originating bills: Senate stages first, then House stages, then Royal Assent.
- Completed stages use `checkmark.circle.fill`.
- Current or next stage uses a neutral current marker, not a completed marker.
- Future stages are visually available but lower emphasis.
- Each stage row includes date when source data provides one.

Data gap:

- Current `BillsService` has first/second/third readings and Royal Assent. Committee/report stage support should wait until the ingestion layer exposes those fields reliably.

### 4. Debate Excerpts

Purpose: let a user inspect what MPs said about the bill without manually searching Hansard.

Initial version:

- Show up to three relevant Hansard subjects already available locally.
- Each item links into `SpeechView` when a matching `Hansard` and subject can be resolved.
- Empty state is omitted if no local debates match; do not display a "no debates" claim unless the backend search index has complete coverage for the bill.

Future backend-backed version:

- Use the Hansard speech index to query exact bill-number mentions and bill aliases.
- Sort by recency, then by stage relevance.
- Include source date and sitting context.

### 5. Recorded Votes

Purpose: show decisions, not only debate.

Rows:

- Vote description.
- Vote date.
- Yea/Nay totals.
- User's MP vote when resolvable.
- Link to vote detail.

Behavior:

- Match by structured `billNumberCode` first.
- Text matching is a fallback only when structured vote metadata is absent.
- If multiple votes exist, most recent first.

### 6. Costing Notes

Purpose: surface independent fiscal analysis when available.

Behavior:

- Keep `PBOCostCard` below key facts and above timeline when a match exists.
- Use PBO title, publication date, and official link.
- If no PBO match exists, omit the section.

### 7. Actions

Primary actions:

- Follow or unfollow.
- Share.
- Contact My MP.

Secondary actions:

- Open official LEGISinfo page.
- Search this bill across the app.

Action placement:

- Follow and share remain toolbar actions for reachability.
- Contact My MP belongs in the lower action section because it requires context.
- Official source link should be visible in both Key Facts and lower actions only if it does not create duplicate visual noise; otherwise prefer Key Facts.

## States

### Loading

- Use existing bill row skeletons on list pages.
- Detail pages should avoid skeletons when navigated from an already-loaded `Bill`; only deferred cross-references need inline loading affordances.

### Partial Data

- Render source-backed fields that exist.
- Omit unknown optional sections.
- Never show placeholder claims such as "No PBO costing" unless the data source was queried successfully.

### Offline or Fetch Failed

- If the user opened a bill from an already-loaded list, keep the detail page usable.
- Show failures only for sections that require additional loading, such as cross-references.

## Accessibility

- Header and timeline rows must use combined labels that include bill number, status, stage name, and date.
- Color cannot be the only status cue.
- Timeline icons should be hidden from VoiceOver when the combined row label already states completion.
- Follow button label must switch between "Follow bill" and "Unfollow bill".
- Dynamic Type must keep title, badges, and toolbar actions readable at accessibility sizes.
- VoiceOver order: header, key facts, costing, timeline, votes, debates, actions, data source.

## Implementation Slices

1. Header and key facts refresh.
2. Sponsor card with member-profile link.
3. Timeline component extraction and current-stage marker.
4. Vote rows linking to `VoteDetailView`.
5. Debate excerpt rows backed by the search index.
6. Official source link cleanup and Search-this-bill action.
7. Accessibility snapshot pass for large Dynamic Type and VoiceOver labels.

## Acceptance Criteria

- The bill page uses only source-backed data.
- The first viewport identifies the bill, status, type, sponsor, and current stage.
- The timeline distinguishes completed, current, and future stages.
- Votes and debate sections are omitted when source-backed cross-references are unavailable.
- Follow, share, Contact My MP, and official source actions are reachable without duplicating primary content.
- VoiceOver users can understand status and timeline without relying on color or icon shape.

## Open Questions

- Should committee/report stages be modeled as first-class `BillStage` cases or derived from raw LEGISinfo event history?
- Should "Search this bill" prefill Search with only the bill number or include quoted title aliases?
- Should Home followed-bill cards reuse the same compact header component to avoid two bill-summary designs?
