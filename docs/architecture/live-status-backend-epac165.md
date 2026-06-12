# EPAC-165 Live Status Backend

> Retired by EPAC-1921. The `live-status` Lambda and `/api/v1/live` route have been removed from desired infrastructure state; this document remains as historical architecture context.

## Upstream Research

The House of Commons home page (`https://www.ourcommons.ca/en`) renders the "In the House" widget server-side before its SignalR client attaches. On April 28, 2026, a request with `User-Agent: epac/1.0 (mailto:sunny@riddimsoftware.com)` returned:

- `id="isMeetingInProgress" value="True"`
- `<span class="sync-view">The House is currently sitting.</span>`
- `<span class="now-in-the-house-title">Oral Questions</span>`
- a "Current Member Speaking" block with a member profile link
- `id="hoc-real-time-service" data-url="https://realtimeevents.ourcommons.ca"`

The JavaScript at `https://www.ourcommons.ca/js/nowinthehouse.min.js` creates a SignalR proxy named `RealTimeEventHub` and listens for `updateNowInTheHouse`. SignalR is useful evidence that the widget is fed by a real-time service, but it is not a clean polling API for Lambda: it is connection-oriented and its generated hub endpoint disables JavaScript proxy generation.

## Implementation Choice

The `live-status` Lambda polls the server-rendered House home page during likely sitting windows, parses the widget HTML, and stores the result in the singleton `live_session` table. `GET /api/v1/live` reads that cached row, so app requests do not hit parliament.ca and can respond from Postgres in well under 200ms when the database is healthy.

The poller sends an identifying User-Agent. It is intended to be invoked by EventBridge every two minutes; the handler itself suppresses upstream requests outside sitting windows:

- Monday 10:30-19:00 Ottawa time
- Tuesday through Thursday 09:30-19:00 Ottawa time
- Friday 09:30-15:00 Ottawa time
- no weekend polling

The repository Makefile includes the operational command:

```bash
cd backend && make schedule-rate-lambda SERVICE=live-status FUNCTION_NAME=epac-live-status-staging RATE="rate(2 minutes)"
cd backend && make schedule-rate-lambda SERVICE=live-status FUNCTION_NAME=epac-live-status-production RATE="rate(2 minutes)"
```

Before polling the live widget, the Lambda refreshes the annual sitting calendar (`https://www.ourcommons.ca/en/sitting-calendar/{year}`) at most once per day and caches `chamber-meeting` dates in `live_sitting_day`. If the current date is confirmed as a non-sitting day, it records `is_sitting=false` and skips the live widget request.

## Stability Risk

This depends on public HTML class names and hidden field ids, so it is more fragile than a documented JSON endpoint. The mitigation is keeping parsing small and covered by fixtures, storing the raw status text in `source_snapshot`, and centralizing the upstream call in one Lambda instead of putting HTML parsing in the app. If Parliament exposes a documented endpoint later, only the poller should change.
