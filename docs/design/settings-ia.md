# Settings IA

EPAC-476 establishes one canonical Settings tree so privacy, follows, notifications, language, and future personalization work lands in predictable places.

## Entry Points

- Home tab toolbar: gear icon opens `SettingsView`.
- Tab bar: no Settings tab for v1. The five visible tabs remain focused on repeated civic workflows; Settings stays behind the Home gear until a navigation refactor explicitly adopts a sixth slot or replaces an existing tab.

## Root Sections

### Account

- Postal code and riding change flow.
- Current riding and MP when saved.
- Notifications link.

Account owns identity-adjacent app setup, but epac still has no login account. Postal code and riding data remain local device preferences unless a later backend ticket explicitly changes that contract.

### Appearance

- Theme preference: light, dark, or system.
- App icon alternate when supported.

The current implementation exposes app icon control and records the theme row as the stable home for the later theme preference ticket.

### Language

- App language: English, French, or system.

The current implementation records the section and system value. A later localization ticket can add a real app-language override without moving the row.

### Follows

- Link to follows management.
- Followed bills.
- Followed MPs.
- Followed topics and their notification granularity.

The root Settings screen links to `FollowsSettingsView`; the management view keeps the existing inline delete behaviour for followed bills, MPs, and topics.

### Data & Privacy

- Privacy policy.
- Data handling page.
- Data sources.
- Data export.
- Delete my data.

Export and deletion are present in the IA before their backend or local-data workflows are implemented. They are disabled in the v1 surface so the rows are placed without implying the workflows are ready.

### About

- Version and build.
- Open-source repository.
- Source data credits.
- Brand brief.
- Feedback.
- Rate the app.

About is for provenance and external references. Source data credits stay distinct from the privacy policy because users looking for civic-data provenance should not have to read legal/privacy copy.

### Developer

- Debug-build-only diagnostics.
- Flag overrides.
- Build evidence.

Developer controls are compiled only for debug builds. Release builds should not expose diagnostics or flag overrides unless a later ticket creates a supported public troubleshooting surface.

## Snapshot Coverage

`SnapshotTests.testSettings_root` captures the root Settings surface in light, dark, and accessibility-large Dynamic Type. The snapshot intentionally covers the root IA, not each destination workflow; destination-specific tests belong with the ticket that implements that destination.
