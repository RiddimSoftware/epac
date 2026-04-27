# Sprint-001 Retrospective — 2026-04-27

## What went well
- High-priority V1 foundation tickets (brand brief, ADRs, Sentry) all shipped on day 1.
- Autonomous developer loop was effective: claim → implement → PR → review → merge without manual handoffs.
- Network resilience (EPAC-133) was more thorough than scoped: 19 service files updated vs. the ~5 originally estimated.
- App Store assets (EPAC-109, EPAC-110) found prior committed work in stale branches and built on it rather than starting over.

## What was harder than expected
- Stale "In Progress" tickets (EPAC-158, EPAC-143) had already been merged on different branches — Jira wasn't updated. Cost: ~10 min investigation per ticket.
- EPAC-110 App Preview video recording: `xcrun simctl io recordVideo` requires SIGINT (not SIGTERM) to finalize the MP4. Recording loop had to be retried twice.
- EPAC-109 screenshots: existing remote branch had a rebase-in-progress conflict between the screenshots mode and the offline banner mode. Took one conflict resolution cycle.

## One thing to do differently in Sprint-002
**Keep Jira current in real time.** Two tickets (EPAC-158, EPAC-143) were Done in code but still showed In Progress in Jira. The reviewer should always transition the ticket immediately on merge, not leave it for the next session's audit. Adding a post-merge hook or CI step that auto-transitions on PR merge would eliminate this.

## Velocity
- Committed (High): 5 design/doc tickets — all Done ✅
- Committed (Medium): 14 feature tickets — all Done ✅
- Carry-over to Sprint-002: 0
