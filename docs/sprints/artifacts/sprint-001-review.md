# Sprint-001 Review — 2026-04-27

**Sprint theme:** In-flight carry-in + V1 foundations  
**Sprint dates:** 2026-04-21 – 2026-04-27 (week 1)  
**Velocity:** 19 tickets shipped (committed: High-priority V1 foundations + in-flight carry-ins)

---

## What shipped

### V1 Foundations (High Priority — all Done)
| Ticket | Summary |
|--------|---------|
| EPAC-439 | Brand brief v1 — name, tagline, voice & tone, anti-positioning |
| EPAC-452 | Search index choice — design note (Postgres tsvector vs. Meilisearch) |
| EPAC-453 | Sentry baseline — errors and breadcrumbs across the Python backend |
| EPAC-454 | Canonical bill page — UX spec |
| EPAC-464 | Parsed-speech schema — design ADR |

### Features (Medium Priority — all Done)
| Ticket | PR | Summary |
|--------|----|---------|
| EPAC-299 | #130 | MP speech feed on profile |
| EPAC-381 | #173 | New dot badge on bills introduced since last launch |
| EPAC-117 | — | Federal contracts database |
| EPAC-118 | #171/#172 | Fiscal Monitor: Finance Canada monthly federal revenue and spending |
| EPAC-120 | #174 | Vancouver City Council: agendas, council votes |
| EPAC-232 | #175 | Website: Open Graph image tag for social sharing |
| EPAC-230 | #178 | perf: index SpeechMessage.lastName |
| EPAC-143 | #139 | Settings screen: location, notifications, followed items, about |
| EPAC-158 | #135 | Snapshot tests: swift-snapshot-testing for 5 view types |
| EPAC-133 | #180 | Network resilience: NetworkService universal, offline banner, retry backoff |
| EPAC-115 | #179 | Email newsletter: signup form on website, monthly digest template |
| EPAC-109 | #182 | App Store screenshots refresh: 6 branded 1290×2796 PNGs |
| EPAC-110 | #183 | App Preview video: AppPreviewVideoView 6-scene animated showcase |

---

## Demo notes

- **Settings screen (EPAC-143)**: Postal code, notification toggles, followed items, about section. Accessible from Home tab profile icon.
- **Network resilience (EPAC-133)**: All 19 service files route through NetworkService (exponential backoff). Offline banner at bottom of app when disconnected. Retry buttons debounced 2s.
- **App Store assets (EPAC-109, EPAC-110)**: Six 1290×2796 screenshots in `docs/marketing/screenshots/epac-109/`; animated 6-scene preview mode triggered by `-AppPreviewVideo` launch arg. Both require human App Store Connect upload.
- **Fiscal Monitor (EPAC-118)**: Federal revenue/spending data from Finance Canada in new FederalFinancesView under Accountability tab.

---

## What didn't ship
Nothing — all 19 committed items are Done.

---

## Human follow-up before Sprint-002
- [ ] Upload App Store screenshots to App Store Connect (EPAC-109 — needs 1320×2796 on iPhone 16 Pro Max / 17 Plus simulator first)
- [ ] Record and upload App Preview video to App Store Connect (EPAC-110)
- [ ] Set up Mailchimp and replace placeholder form actions (EPAC-115 — steps in `docs/marketing/newsletter/mailchimp-setup.md`)
- [ ] Complete Jira Sprint-001 in board UI and start Sprint-002
- [ ] Upload TestFlight build: `cd ios && bundle exec fastlane deploy`
