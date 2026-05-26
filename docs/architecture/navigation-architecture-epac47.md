# Navigation Architecture (ADR-001)

**Date:** 2026-04-27
**Status:** Accepted
**Ticket:** EPAC-47

### Context

The iOS app grew from 3 features to 20+. The original Debates / Members / Expenditures tab structure no longer accommodates Bills, Petitions, Topics, e-Petitions, Following, Riding Stats, Consultations, and the planned Home feed. iOS tab bars support 5 items before requiring a "More" overflow, which buries content and harms discoverability.

### Decision

Adopt a 5-tab structure that groups features thematically and positions the personalized Home feed as the primary entry point:

| Tab | Icon | Homes |
|-----|------|-------|
| **Home** | `person.house.fill` | MyMPView: Your MP activity, followed bills, followed topics, petitions, consultations |
| **Parliament** | `building.columns.fill` | Sitting calendar, Hansard debates, Order Paper |
| **Members** | `person.3.sequence.fill` | MP list, profiles, voting records, comparison |
| **Accountability** | `scalemass.fill` | Bills tracker, Expenditures, e-Petitions, Topics |
| **Search** | `magnifyingglass` | Cross-entity full-text search |

### Rationale

- **Home first**: The personalized feed is the highest-engagement surface. Users who have set their MP, followed bills, or followed topics will see relevant content immediately. First-launch users see a clear prompt to set up.
- **Parliament vs. Members**: Sittings are temporal (what happened today); Members are entities (who are these people). Keeping them separate reflects how users approach them.
- **Accountability hub**: Bills, Expenditures, Petitions, and Topics are all *accountability* tools — how Parliament spends, passes, and responds to citizens. Grouping them under one tab makes the civic function legible.
- **Search as a tab**: Search is a power-user tool that spans all entities. Keeping it visible ensures discoverability for advanced users without cluttering primary tabs.

### Rejected alternatives

- **6 tabs**: iOS renders a "More" overflow at 6+, which buries the last tab and breaks muscle memory. Rejected.
- **Sidebar-only on iPhone**: NavigationSplitView on iPhone has inconsistent swipe behaviour and doesn't feel native. Rejected for phone; retained for iPad (already implemented).
- **No Home tab**: Keeping Debates as the primary tab requires every new feature to compete for a tab slot. Rejected — the personalized feed is the right first screen.

### Constraints

- All 5 existing tabs must continue to function during and after the transition.
- iPad uses NavigationSplitView (`AppTab.allCases` sidebar); the tab order maps directly to sidebar order — no separate iPad logic needed.
- New features must state their navigation home in the PR description before merging.
