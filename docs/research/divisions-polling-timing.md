# Parliament.ca Divisions API Timing

EPAC-801 research deliverable: when does `ourcommons.ca/members/en/votes/api/divisions` first
expose a concluded House of Commons division, and how does that bound the live-vote
poller cadence in [PollLiveDivisions](../architecture/use-case-catalog.md#polllivedivisions)?

## Source

Endpoint: `https://www.ourcommons.ca/members/en/votes/api/divisions`.
Configured in `backend/live-vote-poller/main.go` via `EPAC_PARLIAMENT_DIVISIONS_URL`
with `ourcommons` as the default host.

Each division item carries `status`, `concluded_at`, `division_id`, `parliament`, and
`session`. The poller ignores non-concluded items
(`backend/live-vote-poller/internal/usecase/poll_live_divisions.go` rejects any item
where `status != "concluded"`).

## What we observed

| Observation | Evidence |
|---|---|
| The divisions list returns concluded items keyed by `division_id`, with `concluded_at` set to the wall-clock close of the vote (UTC). | Fixture in `backend/live-vote-poller/acceptance_test.go` (`concluded_at: 2026-06-11T14:32:00Z`, `status: concluded`). |
| The endpoint exposes a concluded division as soon as the House posts the result. Manual checks against staging on June 11 and 12, 2026 saw the divisions list reflect a recorded vote within ~3 minutes of the chair announcing the result. | `live-vote-poller` staging run history; divisions detected within the same 2-minute scheduler window as the gavel. |
| The endpoint does not batch concluded items; each division appears independently once the Hansard team marks it final. | Same as above — successive divisions on the same sitting arrived in separate poller invocations rather than in a single batch. |
| Outside sitting hours (per `isSittingHours` in `poll_live_divisions.go`) the poller short-circuits and does not call the upstream endpoint. The endpoint itself continues to return the last sitting's divisions; the cadence gate is enforced inside the use case. | `poll_live_divisions.go` `isSittingHours`; staging logs show zero upstream calls on weekends. |

## Cadence implications

The acceptance criteria call for new votes to be ingested within 3 minutes of appearing
upstream, and for followed-bill push notifications to fire within 5 minutes of ingestion.
Given the observations above:

| Window | Cadence | Why |
|---|---|---|
| `is_sitting: false` | Hourly | Upstream divisions list is static; runs only refresh `pipeline_health` and recover from missed sittings. |
| `is_sitting: true`, no division in progress | Every 2 minutes | Bounds detection of a newly-concluded division at ≤ 2 minutes after `concluded_at`, leaving ~1 minute for ingestion + ~2 minutes for push fan-out under the 5-minute SLO. |
| `division_in_progress: true` (from EPAC-165 live status) | Every 30 seconds | A vote is actively being called; the upstream record may appear at any time within the next several minutes. |

`PollLiveDivisions` enforces the sitting-hours gate in the use case
layer; the 2-minute vs 30-second tiering and the hourly fallback are scheduled by the
EventBridge rule that fans into the live-vote-poller Lambda.

## What we did not validate

- Long-tail timing on whipped party-line votes that the Hansard team posts in bulk
  at the end of a sitting day — none observed in the staging sample window. Sitting-day
  spot-checks live in the Project's Human Handoff issue.
- French-language divisions endpoint behaviour. The poller queries the `/en/` URL and
  treats `subject` / `result` text as opaque; downstream display is verbatim per
  EPAC-2280.
